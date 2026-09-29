import Foundation

// Phone calls: iPhone's own call recording, brought in as audio or as the
// transcript it already wrote, and turned into a call memo.
extension MemoraModel {
  /// Writes the call memo with the model Ask AI is using.
  func summarizeCall(_ id: UUID) {
    generateSummary(
      id,
      choice: .builtIn(.phoneCall),
      configuration: summaryConfiguration(for: defaultSummaryEngineChoice)
    )
  }

  /// Makes a call record from a transcript pasted from the Notes app, and
  /// writes its memo. Lines written as 「名前: 発言」 keep the speaker.
  @discardableResult
  func createCallRecord(fromTranscript text: String, title: String) -> UUID? {
    let segments = Self.callSegments(from: text)
    guard !segments.isEmpty, isStoreWritable() else { return nil }

    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let meeting = Meeting(
      id: UUID(),
      title: trimmedTitle.isEmpty ? "通話" : trimmedTitle,
      createdAt: .now,
      duration: 0,
      source: .phoneCall,
      status: .waitingForSummary,
      summary: "",
      keyPoints: [],
      decisions: [],
      openQuestions: [],
      transcript: segments,
      spaceID: nil,
      audioURL: nil
    )
    meetings.insert(meeting, at: 0)
    persistMeetings()
    noteRealSaveForSampleCleanup()
    selectedTab = .files
    libraryPath = [.meeting(meeting.id)]
    summarizeCall(meeting.id)
    return meeting.id
  }

  /// One segment per line. The pasted text has no times, so every segment
  /// starts at zero rather than at an invented time.
  static func callSegments(from text: String) -> [TranscriptSegment] {
    text
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
      .map { line in
        if let separator = line.firstIndex(where: { $0 == ":" || $0 == "：" }) {
          let speaker = line[..<separator].trimmingCharacters(in: .whitespaces)
          let spoken = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
          // A short label before the colon is a speaker; a long one is a
          // sentence that happens to contain a colon, and digits on both
          // sides are a time such as 10:30.
          let isTime = speaker.last?.isNumber == true && spoken.first?.isNumber == true
          if !speaker.isEmpty, speaker.count <= 20, !spoken.isEmpty, !isTime {
            return TranscriptSegment(id: UUID(), speaker: speaker, speakerIsCertain: true, timestamp: 0, text: spoken)
          }
        }
        return TranscriptSegment(id: UUID(), speaker: "", speakerIsCertain: false, timestamp: 0, text: line)
      }
  }
}
