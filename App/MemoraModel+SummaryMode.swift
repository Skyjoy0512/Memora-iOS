import Foundation

extension MemoraModel {
  /// Reads the shape of one record, so the mode can be decided from what the
  /// record actually holds.
  ///
  /// A record with a transcript is audio the app transcribed. A record
  /// without one came from a document or a link. The speakers are read from
  /// the transcript's segments; a segment with no speaker counts as one
  /// unknown speaker, so a record with unseparated speech is not treated as
  /// a meeting.
  func summaryModeFeatures(for meeting: Meeting) -> SummaryModeFeatures {
    let spoken = meeting.transcript.filter {
      !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    let transcriptText = spoken.map(\.text).joined(separator: "\n")
    let bodyText = transcriptText.isEmpty ? meeting.summary : transcriptText
    let speakers = spoken.compactMap { segment -> String? in
      let identifier = segment.speakerID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let name = segment.speaker.trimmingCharacters(in: .whitespacesAndNewlines)
      let key = identifier.isEmpty ? name : identifier
      return key.isEmpty ? nil : key
    }
    var turns = 0
    var previous: String?
    for speaker in speakers {
      if speaker != previous { turns += 1 }
      previous = speaker
    }
    let isStructured = bodyText
      .split(separator: "\n", omittingEmptySubsequences: false)
      .contains { $0.hasPrefix("#") || $0.hasPrefix("- ") || $0.hasPrefix("* ") }
    return SummaryModeFeatures(
      isAudio: !transcriptText.isEmpty,
      hasURL: bodyText.localizedCaseInsensitiveContains("http://")
        || bodyText.localizedCaseInsensitiveContains("https://"),
      speakerCount: Set(speakers).count,
      speakerTurnCount: turns,
      isStructured: isStructured,
      bodyText: bodyText
    )
  }

  /// The mode for one record, or `unknown` when the record does not say.
  func summaryMode(for meeting: Meeting) -> SummaryMode {
    SummaryModeClassifier.classify(summaryModeFeatures(for: meeting))
  }

  /// The template the person has come to expect for this kind of input.
  ///
  /// It is nil until the person has made the same choice twice, and it is
  /// nil when the choice is a tie. The template must also exist, so a
  /// template that was uninstalled is never used.
  func preferredSummaryTemplateID(for mode: SummaryMode) -> String? {
    guard mode != .unknown, let id = summaryModePreference.preferredTemplateID(for: mode) else { return nil }
    guard summaryChoice(id) != nil else { return nil }
    return id
  }

  /// Keeps what was decided about one record.
  ///
  /// The breadcrumb is the trace of the decision, not a rule: it records the
  /// mode that was read and the template that was finally used, so a later
  /// correction can be compared with it.
  func recordSummaryModeBreadcrumb(recordID: UUID, mode: SummaryMode, templateID: String,
                                    suggestedTemplateID: String?) {
    guard mode != .unknown else { return }
    let breadcrumb = SummaryModeBreadcrumb(recordID: recordID, mode: mode, templateID: templateID,
      decidedAt: .now, wasCorrected: suggestedTemplateID != nil && suggestedTemplateID != templateID)
    summaryModeBreadcrumbs[recordID] = breadcrumb
  }

  /// What was decided about one record.
  func summaryModeBreadcrumb(for recordID: UUID) -> SummaryModeBreadcrumb? {
    summaryModeBreadcrumbs[recordID]
  }

  /// Teaches the app what the person wants for this kind of input.
  ///
  /// The count only grows, so a correction that moves back to the earlier
  /// template is also remembered.
  func learnSummaryModePreference(mode: SummaryMode, templateID: String) {
    guard mode != .unknown else { return }
    summaryModePreference.record(mode: mode, templateID: templateID)
  }
}
