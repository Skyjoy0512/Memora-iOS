import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class LocalVoiceModelStore {
  static let shared = LocalVoiceModelStore()

  private(set) var isInstalled = LocalVoiceModel.isInstalled
  private(set) var isDownloading = false
  private(set) var isVerifying = false
  private(set) var progress: Double = 0
  private(set) var errorMessage: String?
  @ObservationIgnored private var task: Task<Void, Never>?
  @ObservationIgnored private var generation = UUID()

  func install() {
    guard !isDownloading, !isInstalled else { return }
    generation = UUID()
    let run = generation
    isDownloading = true
    isVerifying = false
    progress = 0
    errorMessage = nil
    task = Task { [weak self] in
      guard let self else { return }
      let staging = LocalVoiceModel.directory.appendingPathComponent("\(run).download")
      defer { try? FileManager.default.removeItem(at: staging) }
      do {
        try FileManager.default.createDirectory(at: LocalVoiceModel.directory, withIntermediateDirectories: true)
        var directory = LocalVoiceModel.directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        // A process killed during verification cannot run the staging defer.
        // Only our UUID-named temporary downloads are safe to reclaim on retry.
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
          where file.pathExtension == "download" && UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil {
          try FileManager.default.removeItem(at: file)
        }
        let capacity = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        if let capacity, capacity < LocalVoiceModel.byteCount + 200_000_000 {
          throw LiveVoiceError.unavailable("モデルの導入には約1.6 GBの空き容量が必要です。")
        }
        let delegate = LocalVoiceModelDownloadDelegate { [weak self] value in
          Task { @MainActor in
            guard let self, self.generation == run, self.isDownloading else { return }
            if value - self.progress >= 0.005 || value >= 1 { self.progress = value }
          }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 3_600
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: LocalVoiceModel.downloadURL, delegate: delegate)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
          throw LiveVoiceError.unavailable("モデルをダウンロードできませんでした。通信状態を確認してください。")
        }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temporary, to: staging)
        guard self.generation == run else { return }
        self.isVerifying = true
        let verification = Task.detached(priority: .utility) {
          let attributes = try FileManager.default.attributesOfItem(atPath: staging.path)
          guard (attributes[.size] as? NSNumber)?.int64Value == LocalVoiceModel.byteCount else { return false }
          let file = try FileHandle(forReadingFrom: staging)
          defer { try? file.close() }
          var hash = SHA256()
          while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hash.update(data: chunk)
          }
          return hash.finalize().map { String(format: "%02x", $0) }.joined() == LocalVoiceModel.sha256
        }
        let verified = try await withTaskCancellationHandler {
          try await verification.value
        } onCancel: { verification.cancel() }
        try Task.checkCancellation()
        guard self.generation == run else { return }
        guard verified else { throw LiveVoiceError.unavailable("モデルの検証に失敗しました。もう一度ダウンロードしてください。") }
        if FileManager.default.fileExists(atPath: LocalVoiceModel.fileURL.path) { try FileManager.default.removeItem(at: LocalVoiceModel.fileURL) }
        try FileManager.default.moveItem(at: staging, to: LocalVoiceModel.fileURL)
        try LocalVoiceModel.sha256.write(to: LocalVoiceModel.receiptURL, atomically: true, encoding: .utf8)
        self.isInstalled = true
        self.isDownloading = false
        self.isVerifying = false
        self.task = nil
      } catch {
        guard self.generation == run else { return }
        self.isDownloading = false
        self.isVerifying = false
        self.task = nil
        if !(error is CancellationError), (error as? URLError)?.code != .cancelled {
          self.errorMessage = (error as? LiveVoiceError)?.localizedDescription ?? "モデルを導入できませんでした。通信状態と空き容量を確認してください。"
        }
      }
    }
  }

  func cancel() {
    task?.cancel()
    generation = UUID()
    task = nil
    isDownloading = false
    isVerifying = false
    progress = 0
  }
}
