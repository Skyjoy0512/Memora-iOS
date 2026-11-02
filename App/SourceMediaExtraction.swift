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
    let chunks = try SourceMediaChunk.plan(duration: duration)
    var transcript = SourceMediaTranscript()
    for chunk in chunks {
      try Task.checkCancellation()
      // Only one chunk owns temporary audio at a time, including on failure.
      let stage = try await SourceMediaStaging.shared.acquire()
      defer { stage.remove() }
      guard let export = SourceMediaAudioExport(asset: asset, temporaryDirectory: stage.directory, chunk: chunk) else {
        return .init(blocks: [], notice: "この音声を解析できません。再生可能なファイルを追加してください。原本は保存されています。")
      }
      try await export.write(to: stage.audioURL, stageDirectory: stage.directory)
      try Task.checkCancellation()
      // Importing a file is not permission to upload it to a speech provider.
      let outcome = await TranscriptionService.transcribe(fileURL: stage.audioURL, vocabulary: vocabulary, onDeviceOnly: true)
      try Task.checkCancellation()
      switch outcome {
      case .segments(let segments): try transcript.append(segments, chunk: chunk)
      case .nothingRecognized: continue
      // Never cache or summarize a successful prefix as the whole recording.
      case .failed(let message): return .init(blocks: [], notice: message)
      case .unavailable: return .init(blocks: [], notice: "この端末では端末内の文字起こしを利用できません。原本は保存されています。対応端末で再試行してください。")
      case .cancelled: throw CancellationError()
      }
    }
    return .init(blocks: transcript.blocks,
      notice: transcript.blocks.isEmpty
        ? "音声から発言を読み取れませんでした。原本を確認して再試行できます。"
        : (SourceIntake.kind(for: url) == .video ? "音声の文字起こしです。映像の内容は解析していません。" : nil),
      coverage: .partial)
  }
}
