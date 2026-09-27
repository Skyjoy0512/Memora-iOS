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

  /// The header the engines are given about the meeting itself.
  var headerLines: [String] {
    var lines = [
      "タイトル: \(title)",
      "日時: \(dateText)",
      "長さ: \(MemoraFormat.duration(duration))",
      "話者: \(speakers.isEmpty ? "不明" : speakers.joined(separator: ", "))"
    ]
    if !participantNames.isEmpty {
      lines.append("タグ付けされた参加者: \(participantNames.joined(separator: ", "))")
    }
    return lines
  }
}
