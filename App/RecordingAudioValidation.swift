import AVFoundation
import Foundation

enum RecordingAudioValidation {
  static func duration(_ value: TimeInterval?) -> TimeInterval? {
    value.flatMap { $0.isFinite && $0 > 0 && $0 < Double(Int.max) ? $0 : nil }
  }

  /// Container metadata is checked without decoding a day's audio into memory.
  /// This does not certify every compressed packet; recognition validates later.
  static func readDuration(of url: URL) async -> TimeInterval? {
    guard url.isFileURL else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      try Task.checkCancellation()
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
      guard values.isRegularFile == true, values.isSymbolicLink != true,
            let size = values.fileSize, size > 0 else { return nil }
      let asset = AVURLAsset(url: url)
      let (playable, time) = try await asset.load(.isPlayable, .duration)
      guard playable, try await !asset.loadTracks(withMediaType: .audio).isEmpty else { return nil }
      try Task.checkCancellation()
      return duration(time.seconds)
    } catch { return nil }
  }

  static var unreadableNotice: String {
    String(localized: "録音ファイルは端末に保持していますが、音声の長さを確認できませんでした。中断により開けない可能性があります。元のファイルは変更していません。",
      comment: "Interrupted recording retained without confirming that its audio is readable")
  }

  static var missingNotice: String {
    "録音した音声ファイルを確認できませんでした。文字起こしは開始していません。メモと重要マークは保持しています。保存先と元のファイルを確認してください。"
  }
}
