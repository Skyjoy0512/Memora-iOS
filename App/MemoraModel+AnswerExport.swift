import Foundation

extension MemoraModel {
  func answerExportMarkdown(_ message: AIChatMessage) -> String {
    if let snapshot = message.generatedUI, snapshot.isValid,
       snapshot.fingerprint == JSONRenderSnapshot.fingerprint(message.text), !snapshot.text.isEmpty {
      let markdown = NativeAIInterface.response(message.text).markdown
      return [markdown, snapshot.text].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    return NativeAIInterface.exportMarkdown(message.text) { kind, ids in
      guard canUseInterfaceContext(messageID: message.id) else { return nil }
      switch kind {
      case .taskList, .actionBar, .taskProgress:
        guard ids.allSatisfy({ canUseInterfaceTask($0, messageID: message.id) }) else { return nil }
        let tasks = ids.compactMap { task(id: $0) }
        if kind == .taskProgress {
          return ["\(tasks.count)件中\(tasks.filter(\.isCompleted).count)件が完了"]
        }
        return tasks.map { "\($0.title)（\($0.statusLabel)）" }
      case .calendarPreview:
        return interfaceCalendarEvents(ids, messageID: message.id)?.map {
          let date = $0.start.formatted(date: .abbreviated, time: $0.isAllDay ? .omitted : .shortened)
          return "\($0.title) · \(date)" + ($0.isAllDay ? " · 終日" : "〜" + $0.end.formatted(date: .abbreviated, time: .shortened))
        }
      case .mailDraftCard:
        let drafts = ids.compactMap { interfaceMailDraft($0, messageID: message.id) }
        guard drafts.count == ids.count else { return nil }
        return drafts.map { "\($0.subject)\n\($0.body)" }
      case .documentCard:
        guard ids.allSatisfy({ canOpenInterfaceReference(.document($0), messageID: message.id) }) else { return nil }
        return ids.compactMap { document(id: $0)?.displayTitle }
      case .projectCard:
        guard ids.allSatisfy({ canOpenInterfaceReference(.project($0), messageID: message.id) }) else { return nil }
        return ids.compactMap { space(id: $0)?.name }
      case .sourceList:
        guard ids.allSatisfy({ canOpenInterfaceReference(.meeting($0), messageID: message.id) }) else { return nil }
        return ids.compactMap { id in message.sources.first { $0.meetingID == id }?.title }
      default: return nil
      }
    }
  }

  func savedAnswerDocument(for message: AIChatMessage) -> MemoraDocument? {
    documents.first { $0.sourceAnswerID == message.id && $0.provenance?.workspaceID == currentTeamID }
  }
}
