import CoreML
import CryptoKit
import Foundation

/// The bundled voice activity model, verified before it is used.
///
/// The model ships inside the app, so nothing is downloaded and no
/// credential is involved. The manifest fixes the size and hash of every
/// file in the bundle: a bundle that does not match is refused, and the
/// recording is then transcribed without trimming rather than with an
/// unverified model.
actor VoiceActivityModelAssets {
  static let shared = VoiceActivityModelAssets()
  static let modelName = "silero-vad-unified-256ms-v6.2.1.mlmodelc"
  static let manifestName = "VoiceActivityModelManifest"
  static let folderName = "VoiceActivity"

  private var attemptedLoad = false
  private var loaded: MLModel?

  private struct Asset: Decodable {
    var path: String
    var size: Int
    var hash: String
    var isSHA256: Bool
  }

  /// The verified model, or nil when the bundle does not match the manifest.
  func model() -> MLModel? {
    if !attemptedLoad {
      attemptedLoad = true
      if let url = Self.verifiedModelURL() {
        loaded = try? MLModel(contentsOf: url)
      }
    }
    return loaded
  }

  /// Bitrig flattens the resources while folder references can keep both
  /// the manifest and the compiled model under VoiceActivity.
  static func verifiedModelURL(in bundle: Bundle = .main) -> URL? {
    guard let base = bundle.resourceURL else { return nil }
    let folder = base.appendingPathComponent(folderName, isDirectory: true)
    let manifestURL = bundle.url(forResource: manifestName, withExtension: "json")
      ?? folder.appendingPathComponent(manifestName + ".json")
    guard let data = try? Data(contentsOf: manifestURL),
          let assets = try? JSONDecoder().decode([Asset].self, from: data),
          !assets.isEmpty else { return nil }
    return [base, folder].map { $0.appendingPathComponent(modelName, isDirectory: true) }
      .first { root in assets.allSatisfy { validates($0, at: root) } }
  }

  private static func validates(_ asset: Asset, at root: URL) -> Bool {
    let url = root.appendingPathComponent(asset.path)
    guard let data = try? Data(contentsOf: url), data.count == asset.size else { return false }
    let digest: [UInt8]
    if asset.isSHA256 {
      digest = Array(SHA256.hash(data: data))
    } else {
      var gitBlob = Data("blob \(data.count)\0".utf8)
      gitBlob.append(data)
      digest = Array(Insecure.SHA1.hash(data: gitBlob))
    }
    return digest.map { String(format: "%02x", $0) }.joined() == asset.hash
  }
}
