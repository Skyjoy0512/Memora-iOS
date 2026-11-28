import Foundation

extension MemoraModel {
  /// Saving captions never fetches a video or sends an AI request; the normal summary sheet owns consent.
  func importVideoTranscript(_ text: String, source expected: ProjectSource, context: LocalImportContext?) -> UUID? {
    guard let context, context.isCurrent(in: self), isStoreWritable(),
          let source = source(id: expected.id), source.kind == .youtube,
          source.originalURL == expected.originalURL, source.privacy == expected.privacy,
          source.projectID == expected.projectID,
          let transcript = VideoTranscript.segments(text) else { return nil }
    if let existing = source.metadata?["videoTranscriptMeetingID"].flatMap(UUID.init(uuidString:)),
       meeting(id: existing) != nil { return existing }
    var record = Meeting(id: UUID(), title: source.title, createdAt: .now, duration: 0,
      source: .importFile, status: .waitingForSummary, summary: "", keyPoints: [], decisions: [],
      openQuestions: [], transcript: transcript, spaceID: source.projectID, audioURL: nil)
    record.summaryUseCaseID = VideoSummaryTemplate.useCase.id
    record.privacy = source.privacy
    record.notes = "利用者が貼り付けた字幕・文字起こし。動画の全文・時刻・公開日は未確認。\n" + (source.originalURL?.absoluteString ?? "")
    var candidateSources = projectSources
    guard let index = candidateSources.firstIndex(where: { $0.id == source.id }) else { return nil }
    candidateSources[index].metadata = source.metadata ?? [:]
    candidateSources[index].metadata?["videoTranscriptMeetingID"] = record.id.uuidString
    candidateSources[index].updatedAt = .now
    let candidateMeetings = [record] + meetings
    // The link and the record land together, so an interrupted save cannot create duplicates.
    guard persistBatch(meetings: candidateMeetings, { [
      (key: StorageKey.projectSources, data: try RecordStore.encoded(candidateSources))
    ] }) else { return nil }
    meetings = candidateMeetings
    projectSources = candidateSources
    invalidateProjectEvidence([.source(source.id)])
    return record.id
  }
}
