import CoreML
import CryptoKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif
import os

/// The bundled voice activity model, verified before it is used.
///
/// The model ships inside the app, so nothing is downloaded and no
/// credential is involved. The manifest fixes the size and hash of every
/// file in the bundle: a bundle that does not match is refused, and the
/// recording is then transcribed without trimming rather than with an
/// unverified model.
///
/// The model is loaded on first use, never at launch, and one actor owns it so
/// two recordings cannot build a second copy. A memory warning frees it; the
/// next request verifies and loads it again.
actor VoiceActivityModelAssets {
  static let shared = VoiceActivityModelAssets()
  static let modelName = "silero-vad-unified-256ms-v6.2.1.mlmodelc"
  static let manifestName = "VoiceActivityModelManifest"
  static let folderName = "VoiceActivity"

  private var attemptedLoad = false
  private var loaded: MLModel?
  /// How many predictions are in flight. The model is not freed while one is,
  /// even if the system asks for memory.
  private var activeUses = 0
  /// Frees the model when the system is short of memory. Installed the first
  /// time the model is asked for, so a build that never trims never observes.
  nonisolated(unsafe) private static let memoryObserver: NSObjectProtocol? = {
    #if canImport(UIKit)
    NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
    ) { _ in
      Task { await VoiceActivityModelAssets.shared.release() }
    }
    #else
    nil
    #endif
  }()

  private struct Asset: Decodable {
    var path: String
    var size: Int
    var hash: String
    var isSHA256: Bool
  }

  /// Where the model runs.
  ///
  /// Measured on the host with the bundled model: `.cpuOnly` loads it in 0.6 ms
  /// against 15 ms for `.all`, and `.all` and `.cpuAndNeuralEngine` predict a
  /// 256 ms frame in the same 0.16 ms as the CPU with identical output. The
  /// Neural Engine pays about 15 ms of preparation for a 0.16 ms prediction,
  /// so the CPU is the right placement for this model. Device energy and
  /// thermal behaviour are not measured.
  static let computeUnits: MLComputeUnits = .cpuOnly

  static func configuration(computeUnits: MLComputeUnits = VoiceActivityModelAssets.computeUnits) -> MLModelConfiguration {
    let configuration = MLModelConfiguration()
    configuration.computeUnits = computeUnits
    return configuration
  }

  /// The verified model, or nil when the bundle does not match the manifest.
  func model() -> MLModel? {
    _ = Self.memoryObserver
    if !attemptedLoad {
      attemptedLoad = true
      if let url = Self.verifiedModelURL() {
        loaded = try? MLModel(contentsOf: url, configuration: Self.configuration())
      }
    }
    return loaded
  }

  /// Runs `work` while holding the loaded model, so a memory warning in the
  /// middle of a prediction frees nothing that is still being read.
  func withModel<T>(_ work: (MLModel) async throws -> T) async rethrows -> T? {
    guard let model = model() else { return nil }
    activeUses += 1
    defer { activeUses -= 1 }
    return try await work(model)
  }

  /// Frees the model after a memory warning. The next request loads it again
  /// from the verified bundle; nothing is kept in memory between uses.
  func release() {
    guard activeUses == 0, loaded != nil else { return }
    loaded = nil
    attemptedLoad = false
    Logger(subsystem: "app.memora.audio", category: "VoiceActivity").info("Released the voice activity model")
  }

  var isLoaded: Bool { loaded != nil }

  /// Bitrig flattens the resources while folder references can keep both
  /// the manifest and the compiled model under VoiceActivity.
  static func verifiedModelURL(in bundle: Bundle = .main) -> URL? {
    guard let base = bundle.resourceURL else { return nil }
    let folder = base.appendingPathComponent(folderName, isDirectory: true)
    let manifestURL = bundle.url(forResource: manifestName, withExtension: "json")
      ?? folder.appendingPathComponent(manifestName + ".json")
    return verifiedModelURL(root: base, fallbackRoot: folder, manifestURL: manifestURL)
  }

  /// Verifies the assets under `root`, then `fallbackRoot`, without reading a
  /// model-sized file into one buffer: each asset is hashed as it streams off
  /// disk, so verifying does not double the peak memory of loading.
  static func verifiedModelURL(root: URL, fallbackRoot: URL?, manifestURL: URL) -> URL? {
    guard let data = try? Data(contentsOf: manifestURL),
          let assets = try? JSONDecoder().decode([Asset].self, from: data),
          !assets.isEmpty else { return nil }
    for directory in [root, fallbackRoot].compactMap({ $0 }) {
      if assets.allSatisfy({ validates($0, at: directory) }) {
        return directory.appendingPathComponent(modelName, isDirectory: true)
      }
    }
    return nil
  }

  private static func validates(_ asset: Asset, at root: URL) -> Bool {
    let url = root.appendingPathComponent(asset.path)
    guard let digest = digest(of: url, asGitBlob: !asset.isSHA256) else { return false }
    guard digest.count == asset.size else { return false }
    return digest.hex == asset.hash
  }

  private struct FileDigest {
    var count: Int
    var hex: String
  }

  /// Streams the file so a large compiled model never has to sit in a `Data`
  /// beside the copy Core ML is about to map.
  private static func digest(of url: URL, asGitBlob: Bool) -> FileDigest? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    var count = 0
    if asGitBlob {
      var sha1 = Insecure.SHA1()
      // A git blob hash covers its own header before the content.
      guard let size = try? handle.seekToEnd() else { return nil }
      count = Int(size)
      try? handle.seek(toOffset: 0)
      sha1.update(data: Data("blob \(count)\0".utf8))
      while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
        sha1.update(data: chunk)
      }
      return FileDigest(count: count, hex: sha1.finalize().map { String(format: "%02x", $0) }.joined())
    }
    var sha256 = SHA256()
    while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
      count += chunk.count
      sha256.update(data: chunk)
    }
    return FileDigest(count: count, hex: sha256.finalize().map { String(format: "%02x", $0) }.joined())
  }
}
