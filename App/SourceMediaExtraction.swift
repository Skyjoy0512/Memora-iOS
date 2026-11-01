import AVFoundation
import Foundation

enum SourceMediaExtraction {
  static func extract(_ url: URL, vocabulary: [String]) async throws -> ProjectSourceExtractionResult {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let asset = AVURLAsset(url: url)
    guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
      return .init(blocks: [], notice: "音声トラックがありません。映像の内容は解析していません。")
    }
    let duration = try await asset.load(.duration).seconds
    guard duration.isFinite, duration > 0, duration <= 6 * 60 * 60,
          let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
      return .init(blocks: [], notice: "この音声を解析できません。6時間以内の再生可能なファイルを追加してください。原本は保存されています。")
    }
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("memora-audio-\(UUID()).m4a")
    defer { try? FileManager.default.removeItem(at: temporary) }
    try Task.checkCancellation()
    try await session.export(to: temporary, as: .m4a)
    try Task.checkCancellation()
    // Importing a file is not permission to upload it to a speech provider.
    let outcome = await TranscriptionService.transcribe(fileURL: temporary, vocabulary: vocabulary, onDeviceOnly: true)
    try Task.checkCancellation()
    switch outcome {
    case .segments(let segments):
      return .init(blocks: segments.flatMap { SourceTextChunks.split($0.text, time: $0.timestamp) },
        notice: SourceIntake.kind(for: url) == .video ? "音声の文字起こしです。映像の内容は解析していません。" : nil,
        coverage: .partial)
    case .failed(let message): return .init(blocks: [], notice: message)
    case .nothingRecognized: return .init(blocks: [], notice: "音声から発言を読み取れませんでした。原本を確認して再試行できます。")
    case .unavailable: return .init(blocks: [], notice: "この端末では端末内の文字起こしを利用できません。原本は保存されています。対応端末で再試行してください。")
    case .cancelled: throw CancellationError()
    }
  }
}
