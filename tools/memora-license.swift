#!/usr/bin/env swift
// Issues Memora enterprise license codes, signed with Ed25519.
//
//   swift tools/memora-license.swift keygen [private-key-path]
//   swift tools/memora-license.swift issue --company "株式会社サンプル" --plan unlimited --seats 20 --days 365 [--key path]
//
// The private key stays outside the repository (default ~/.memora/license-private.key).
// The public key `keygen` prints goes into Project.json as MemoraLicensePublicKey.

import CryptoKit
import Foundation

let defaultKeyPath = NSString(string: "~/.memora/license-private.key").expandingTildeInPath

func base64URL(_ data: Data) -> String {
  data.base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}

func value(_ flag: String, in args: [String]) -> String? {
  guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
  return args[index + 1]
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "keygen":
  let path = args.count > 1 ? NSString(string: args[1]).expandingTildeInPath : defaultKeyPath
  guard !FileManager.default.fileExists(atPath: path) else {
    fail("秘密鍵はすでにあります: \(path)（上書きしません）")
  }
  let key = Curve25519.Signing.PrivateKey()
  try FileManager.default.createDirectory(
    atPath: (path as NSString).deletingLastPathComponent,
    withIntermediateDirectories: true
  )
  FileManager.default.createFile(
    atPath: path,
    contents: Data(key.rawRepresentation.base64EncodedString().utf8),
    attributes: [.posixPermissions: 0o600]
  )
  print("秘密鍵を保存しました: \(path)")
  print("MemoraLicensePublicKey: \(key.publicKey.rawRepresentation.base64EncodedString())")

case "issue":
  let path = value("--key", in: args).map { NSString(string: $0).expandingTildeInPath } ?? defaultKeyPath
  guard let stored = try? String(contentsOfFile: path, encoding: .utf8),
        let raw = Data(base64Encoded: stored.trimmingCharacters(in: .whitespacesAndNewlines)),
        let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
    fail("秘密鍵を読めません: \(path)")
  }
  guard let company = value("--company", in: args) else { fail("--company が必要です") }
  let plan = value("--plan", in: args) ?? "unlimited"
  guard ["light", "pro", "unlimited", "team"].contains(plan) else { fail("--plan は light / pro / unlimited / team") }
  let seats = Int(value("--seats", in: args) ?? "1") ?? 1
  let days = Double(value("--days", in: args) ?? "365") ?? 365
  let payload: [String: Any] = [
    "id": UUID().uuidString,
    "company": company,
    "plan": plan,
    "seats": seats,
    "expiresAt": Int(Date().addingTimeInterval(days * 86_400).timeIntervalSince1970)
  ]
  let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
  let signature = try key.signature(for: body)
  print("MEMORA-\(base64URL(body)).\(base64URL(signature))")

default:
  print("使い方: swift tools/memora-license.swift keygen | issue --company 名前 --plan unlimited --seats 20 --days 365")
}
