import Foundation

// Follow-up questions offered under an answer. They are built from what the
// records the answer read really hold — decisions, unfinished tasks, open
// questions — so each one has something behind it to answer from.
extension MemoraModel {
  func followUps(for message: AIChatMessage) -> [String] {
    guard message.role == .assistant, !message.isThinking, !message.isAgentReply,
          !isAIChatResponding, message.id == aiMessages.last?.id else { return [] }

    var prompts: [String] = []
    for source in message.sources.prefix(3) {
      guard let meeting = meeting(id: source.meetingID) else { continue }
      let title = meeting.displayTitle
      if !meeting.decisions.isEmpty {
        prompts.append("「\(title)」で決まったことを詳しく")
      }
      if tasks(forMeeting: meeting.id).contains(where: { !$0.isCompleted }) {
        prompts.append("「\(title)」で残っているタスクは？")
      }
      if !meeting.openQuestions.isEmpty {
        prompts.append("「\(title)」で決まっていないことは？")
      }
    }
    // A question already asked in this conversation is not offered again.
    let asked = Set(aiMessages.filter { $0.role == .user }.map(\.text))
    var seen: Set<String> = []
    return prompts.filter { !asked.contains($0) && seen.insert($0).inserted }.prefix(3).map { $0 }
  }
}
