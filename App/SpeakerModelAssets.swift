import CryptoKit
import Foundation

actor SpeakerModelAssets {
  static let shared = SpeakerModelAssets()
  static let revision = "df2625ac79a7ac6b65ad868fee6d80f320da4232"
  static let modelID = "FluidInference/community-1/embedding256"
  static let requiredBytes: Int64 = 21_634_526
  private var isInstalling = false

  static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("SpeakerModels/\(revision)", isDirectory: true)
  }

  static var isInstalled: Bool {
    FileManager.default.fileExists(atPath: directory.appendingPathComponent("installed").path)
  }

  private struct Asset: Decodable {
    var path: String
    var size: Int
    var hash: String
    var isSHA256: Bool
  }

  private func manifest() throws -> [Asset] {
    guard let url = Bundle.main.url(forResource: "SpeakerModelManifest", withExtension: "json") else {
      throw SpeakerProcessingFailure.assetsInvalid
    }
    return try JSONDecoder().decode([Asset].self, from: Data(contentsOf: url))
  }

  func verifiedDirectory() throws -> URL {
    guard Self.isInstalled else { throw SpeakerProcessingFailure.modelsMissing }
    for asset in try manifest() {
      guard try validates(asset, at: Self.directory.appendingPathComponent(asset.path)) else {
        throw SpeakerProcessingFailure.assetsInvalid
      }
    }
    return Self.directory
  }

  func install(progress: @escaping @Sendable (Int, Int) async -> Void) async throws {
    guard !isInstalling else { throw SpeakerProcessingFailure.busy }
    isInstalling = true
    defer { isInstalling = false }
    var directory = Self.directory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try directory.setResourceValues(values)
    let available = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage ?? 0
    guard available > Self.requiredBytes * 3 else { throw CocoaError(.fileWriteOutOfSpace) }
    let assets = try manifest()
    for (index, asset) in assets.enumerated() {
      try Task.checkCancellation()
      let destination = directory.appendingPathComponent(asset.path)
      if try !validates(asset, at: destination) {
        guard let url = URL(string: "https://huggingface.co/FluidInference/speaker-diarization-coreml/resolve/\(Self.revision)/\(asset.path)") else {
          throw SpeakerProcessingFailure.assetsInvalid
        }
        let (temporary, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              try validates(asset, at: temporary) else { throw SpeakerProcessingFailure.assetsInvalid }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Data(contentsOf: temporary)
        try data.write(to: destination, options: .atomic)
      }
      await progress(index + 1, assets.count)
    }
    try Task.checkCancellation()
    try Data(Self.revision.utf8).write(to: directory.appendingPathComponent("installed"), options: .atomic)
  }

  private func validates(_ asset: Asset, at url: URL) throws -> Bool {
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    let data = try Data(contentsOf: url)
    guard data.count == asset.size else { return false }
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
