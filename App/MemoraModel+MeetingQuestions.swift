import Foundation

extension MemoraModel {
  @discardableResult
  func stageMeetingQuestion(_ question: String, snapshot: MeetingSummaryPosterSnapshot) -> Bool {
    guard snapshot.isCurrent(in: self), activeDetailMeetingID == snapshot.meetingID,
          activeDetailTabs.last == selectedTab, activeProjectChatID == nil,
          composerDraft.isEmpty, composerAttachment == nil, composerMentions.isEmpty,
          !isAIChatResponding else { return false }
    let currentQuestions = MeetingQuestionSuggestions.make(summary: snapshot.summary,
      infographic: MeetingInfographicSample.resolve(snapshot))
    guard currentQuestions.contains(question) else { return false }
    // This is still the record composer; its normal send-time privacy and
    // scope checks apply. A suggestion is neither a send nor a tool grant.
    composerDraft = question
    composerFocusRequest = UUID()
    return true
  }
}
