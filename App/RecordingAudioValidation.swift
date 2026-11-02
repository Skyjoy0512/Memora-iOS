import AVFoundation
import Foundation

enum RecordingAudioValidation {
  static func frameCount(of url: URL, sampleRate: Int) async -> Int64? {
    guard !Task.isCancelled else { return nil }
    let operation = Task.detached(priority: .utility) { () -> Int64? in
      guard !Task.isCancelled, url.isFileURL, (8_000...192_000).contains(sampleRate) else { return nil }
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      do {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let before = try url.resourceValues(forKeys: keys)
        guard before.isRegularFile == true, before.isSymbolicLink != true, (before.fileSize ?? 0) > 0 else { return nil }
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate == Double(sampleRate), file.processingFormat.channelCount > 0,
              file.length > 0, file.length <= Int64(sampleRate) * 86_400 else { return nil }
        let after = try url.resourceValues(forKeys: keys)
        guard !Task.isCancelled, after.isRegularFile == true, after.isSymbolicLink != true,
              before.fileSize == after.fileSize, before.contentModificationDate == after.contentModificationDate else { return nil }
        return file.length
      } catch { return nil }
    }
    let result = await withTaskCancellationHandler { await operation.value } onCancel: { operation.cancel() }
    return Task.isCancelled ? nil : result
  }

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

  static var manifestNotice: String {
    "録音の復旧情報を確認できませんでした。保存情報と下書きは保持しています。新しい録音は開始していません。"
  }

  static var segmentedNotice: String {
    "録音の保存情報とメモを保持しました。連続した音声としての準備を完了できなかったため、文字起こしは開始していません。元のファイルを確認してください。"
  }
}
