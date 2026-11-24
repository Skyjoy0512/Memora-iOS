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

  private var isLoading = false
  private var loaded: MLModel?

  private struct Asset: Decodable {
    var path: String
    var size: Int
    var hash: String
    var isSHA256: Bool
  }

  /// The verified model, or nil when the bundle does not match the manifest.
  func model() -> MLModel? {
    if let loaded { return loaded }
    guard !isLoading else { return nil }
    isLoading = true
    defer { isLoading = false }
    guard let model = Self.loadVerifiedModel() else { return nil }
    loaded = model
    return model
  }

  /// Whether the bundled model matches its manifest.
  static func isUsable() -> Bool {
    guard let root = bundleRoot(), let assets = manifest(),
          assets.allSatisfy({ validates($0, at: root) }) else { return false }
    return FileManager.default.fileExists(atPath: root.appendingPathComponent(modelName).path)
  }

  private static func bundleRoot() -> URL? {
    guard let base = Bundle.main.resourceURL else { return nil }
    let root = base.appendingPathComponent(folderName, isDirectory: true)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
          isDirectory.boolValue else { return nil }
    return root
  }

  private static func manifest() -> [Asset]? {
    guard let url = Bundle.main.url(forResource: manifestName, withExtension: "json") else { return nil }
    return try? JSONDecoder().decode([Asset].self, from: Data(contentsOf: url))
  }

  private static func loadVerifiedModel() -> MLModel? {
    guard let root = bundleRoot(), let assets = manifest(),
          assets.allSatisfy({ validates($0, at: root) }) else { return nil }
    let modelURL = root.appendingPathComponent(modelName, isDirectory: true)
    guard let model = try? MLModel(contentsOf: modelURL) else { return nil }
    return model
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
