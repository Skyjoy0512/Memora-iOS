import Foundation

// Ask AI as a personal assistant: what it remembers about the person and the
// past conversations it can draw on.
extension MemoraModel {
  /// The longest a single memory may be, so one entry cannot crowd the rest.
  static let aiMemoryCharacterLimit = 200

  // MARK: - Memories

  /// Keeps something about the person. Returns false for an empty text or one
  /// already remembered.
  @discardableResult
  func addAIMemory(_ text: String, origin: AIMemory.Origin) -> Bool {
    let trimmed = String(
      text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.aiMemoryCharacterLimit)
    )
    guard !trimmed.isEmpty,
          !aiMemories.contains(where: { $0.text.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
      return false
    }
    aiMemories.insert(AIMemory(id: UUID(), text: trimmed, origin: origin, createdAt: .now), at: 0)
    persistAIMemories()
    return true
  }

  func updateAIMemory(_ id: UUID, text: String) {
    let trimmed = String(
      text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.aiMemoryCharacterLimit)
    )
    guard let index = aiMemories.firstIndex(where: { $0.id == id }) else { return }
    if trimmed.isEmpty {
      aiMemories.remove(at: index)
    } else {
      aiMemories[index].text = trimmed
    }
    persistAIMemories()
  }

  func deleteAIMemories(_ ids: Set<UUID>) {
    aiMemories.removeAll { ids.contains($0.id) }
    persistAIMemories()
  }

  func deleteAllAIMemories() {
    aiMemories = []
    persistAIMemories()
  }

  /// What a question asked to be remembered, when it says so plainly:
  /// "〇〇を覚えておいて", "〇〇と覚えて", "〇〇って記憶して". The rest of the
  /// question is kept as written; nothing is inferred.
  static func explicitMemory(in question: String) -> String? {
    let triggers = ["覚えておいてください", "覚えておいて", "覚えといて", "覚えてて", "覚えて", "記憶しておいて", "記憶して"]
    var text = question.trimmingCharacters(in: .whitespacesAndNewlines)
    for mark in ["。", "！", "!", "？", "?", "ね", "よ"] where text.hasSuffix(mark) {
      text.removeLast(mark.count)
    }
    guard let trigger = triggers.first(where: { text.hasSuffix($0) }) else { return nil }
    text.removeLast(trigger.count)
    // The particle that ties the content to the request.
    for particle in ["ことを", "のを", "って", "と", "を", "は"] where text.hasSuffix(particle) {
      text.removeLast(particle.count)
      break
    }
    let content = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "、,")))
    return content.count >= 2 ? content : nil
  }

  // MARK: - What a question carries

  /// The memories and the past conversations that bear on a question, as one
  /// block for the prompt, within `budget` characters. Empty when memory is off.
  func personalContext(for question: String, budget: Int, includesHistory: Bool = true) -> String {
    guard isAIMemoryEnabled, budget > 80 else { return "" }
    var parts: [String] = []
    var remaining = budget

    if !aiMemories.isEmpty {
      var lines = ["利用者について覚えていること（利用者が伝えた内容。事実として扱い、聞き返さない）:"]
      var used = lines[0].count
      for memory in aiMemories {
        let line = "- \(memory.text)"
        guard used + line.count + 1 <= remaining * 3 / 5 else { break }
        lines.append(line)
        used += line.count + 1
      }
      if lines.count > 1 {
        let block = lines.joined(separator: "\n")
        parts.append(block)
        remaining -= block.count
      }
    }

    let past = includesHistory ? relevantPastExchanges(for: question, budget: remaining) : ""
    if !past.isEmpty {
      parts.append(past)
    }
    return parts.joined(separator: "\n\n")
  }

  /// Earlier questions and answers that share words with this one, from
  /// conversations other than the open one, so "前に話した件" can be followed.
  private func relevantPastExchanges(for question: String, budget: Int) -> String {
    let words = Self.questionWords(in: question)
    guard !words.isEmpty, budget > 120 else { return "" }
    let open = Set(aiMessages.filter { $0.role == .user }.map(\.text))

    var scored: [(entry: AIConversationEntry, score: Int)] = []
    for entry in aiHistory where !open.contains(entry.question) {
      let text = entry.question + "\n" + entry.answer
      let score = words.filter { text.localizedCaseInsensitiveContains($0) }.count
      if score > 0 {
        scored.append((entry, score))
      }
    }
    scored.sort { lhs, rhs in
      if lhs.score != rhs.score { return lhs.score > rhs.score }
      return lhs.entry.createdAt > rhs.entry.createdAt
    }
    let ranked = scored.prefix(3)
    guard !ranked.isEmpty else { return "" }

    var lines = ["以前の会話から関係しそうなもの（参考。古い可能性がある）:"]
    var used = lines[0].count
    for item in ranked {
      let date = item.entry.createdAt.formatted(date: .numeric, time: .omitted)
      let answer = item.entry.answer.replacingOccurrences(of: "\n", with: " ")
      let line = "- \(date) 利用者: \(item.entry.question) / 回答: \(answer.prefix(240))"
      guard used + line.count + 1 <= budget else { break }
      lines.append(line)
      used += line.count + 1
    }
    return lines.count > 1 ? lines.joined(separator: "\n") : ""
  }

  // MARK: - Continuing

  /// Opens a saved exchange as the conversation, so a follow-up can be asked
  /// with it in view.
  func continueAIConversation(from entry: AIConversationEntry) {
    startNewAIChat()
    aiMessages = [
      AIChatMessage(role: .user, text: entry.question),
      AIChatMessage(role: .assistant, text: entry.answer, cloudProvenance: entry.cloudProvenance)
    ]
    if let id = entry.webResearchReportID, webResearch(id: id)?.isChatSearch == true {
      aiMessages[1].webResearchReportIDs = [id]
      return
    }
    if AIEngineService.effectiveEngine(askAIConfiguration.engine) == .cloud,
       !canReuseCloudConversation(entry.cloudProvenance) {
      aiMessages.append(AIChatMessage(role: .assistant,
        text: "この履歴は出典・内容・現在の許可を確認できないため、クラウドへ再送しません。表示はそのまま残します。続きに必要な情報は、新しい質問で指定してください。"))
    }
  }
}

extension MemoraModel {
  /// The line in the conversation that says something was remembered.
  static func memoryNote(_ text: String) -> AIChatMessage {
    AIChatMessage(role: .assistant, text: "「\(text)」を覚えました。設定の「メモリ」でいつでも確認・削除できます。")
  }

  /// Places the note just after the person's message, before the agent's
  /// reply that is already on its way.
  func insertMemoryNote(_ text: String) {
    guard let index = aiMessages.lastIndex(where: { $0.role == .user }) else { return }
    aiMessages.insert(Self.memoryNote(text), at: index + 1)
  }
}
