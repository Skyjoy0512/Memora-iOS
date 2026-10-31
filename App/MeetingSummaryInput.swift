import Foundation

/// Everything a summary is written from, captured once on the main actor so
/// the engines work on a stable copy.
struct MeetingSummaryInput {
  var title: String
  var date: Date
  var duration: TimeInterval
  var participantNames: [String]
  var transcript: [TranscriptSegment]
  var template: SummaryTemplateChoice
  /// Terms whose spelling the summary should follow.
  var glossary: [String] = []
  var preferences = SummaryPreferences()
  var automaticCandidates: [SummaryTemplateChoice] = []

  /// Speaker labels in the order they first spoke.
  var speakers: [String] {
    var seen: Set<String> = []
    return transcript.compactMap { segment in
      let name = segment.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !name.isEmpty, seen.insert(name).inserted else { return nil }
      return name
    }
  }

  var dateText: String {
    date.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: "ja_JP")))
  }

  /// One line per utterance, `[mm:ss] 話者: 本文`, so the engine can place
  /// topics in time and attribute what was said.
  static func line(for segment: TranscriptSegment) -> String {
    let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
    return "[\(MemoraFormat.duration(segment.timestamp))] \(segment.speaker): \(text)"
  }

  static func cloudLine(for segment: TranscriptSegment) -> String {
    let time = segment.timestamp.isFinite && segment.timestamp >= 0 && segment.timestamp < Double(Int.max)
      ? MemoraFormat.duration(segment.timestamp) : "時刻不明"
    return "[\(time)] [segmentID=\(segment.id.uuidString)] \(segment.speaker): \(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))"
  }

  func transcriptLine(for segment: TranscriptSegment, cloud: Bool = false) -> String {
    guard duration <= 0 else { return cloud ? Self.cloudLine(for: segment) : Self.line(for: segment) }
    let identity = cloud ? " [segmentID=\(segment.id.uuidString)]" : ""
    return "[時刻不明]\(identity) \(segment.speaker): \(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))"
  }

  /// The header the engines are given about the meeting itself.
  var headerLines: [String] {
    var lines = [
      "タイトル: \(title)",
      "記録の保存日時（公開日・収録日ではない）: \(dateText)",
      duration > 0 ? "長さ: \(MemoraFormat.duration(duration))" : "長さ・時刻情報: 不明",
      "話者: \(speakers.isEmpty ? "不明" : speakers.joined(separator: ", "))"
    ]
    if !participantNames.isEmpty {
      lines.append("タグ付けされた参加者: \(participantNames.joined(separator: ", "))")
    }
    if !glossary.isEmpty {
      // The recogniser can still mishear these; the summary writes them as
      // listed when the transcript clearly means one of them.
      lines.append("用語集（文字起こしの誤認識がこれらを指すと明らかな場合は、この表記に直す）: \(glossary.joined(separator: "、"))")
    }
    return lines
  }
}
