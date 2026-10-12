import Foundation

extension MemoraModel {
  var latestChatWebQuery: String? {
    guard let message = aiMessages.last(where: { $0.role == .assistant }),
          let id = message.webResearchReportIDs.last,
          let report = webResearch(id: id), report.isChatSearch == true else { return nil }
    return report.query
  }

  @discardableResult
  func sendWebSearchChat(_ question: String, query: String?) -> Bool {
    guard !isAIChatResponding else { return false }
    aiMessages.append(AIChatMessage(role: .user, text: question))
    guard let query else {
      aiMessages.append(AIChatMessage(role: .assistant, text: "何を検索しますか？知りたい内容を送ってください。"))
      return true
    }
    guard KeychainStore.has(WebResearchClient.keyName) else {
      aiMessages.append(AIChatMessage(role: .assistant, text: "Web検索はまだ接続されていません。設定 → AI整理 → Web検索でBrave Search APIキーを登録すると、このチャットから検索できます。"))
      return true
    }
    let reportID: UUID
    do {
      guard let id = try createWebResearch(query: query, mode: .search, queries: [query]),
            var report = webResearch(id: id) else { throw WebResearchClient.Failure.invalidResponse }
      report.isChatSearch = true
      guard storeWebResearch(report) else { throw WebResearchClient.Failure.invalidResponse }
      reportID = id
    } catch {
      aiMessages.append(AIChatMessage(role: .assistant, text: error.localizedDescription))
      return true
    }
    let requestID = UUID()
    aiChatRequestID = requestID
    var reply = AIChatMessage(role: .assistant, text: "", isThinking: true)
    reply.webResearchReportIDs = [reportID]
    aiMessages.append(reply)
    isAIChatResponding = true
    aiChatTask?.cancel()
    aiChatTask = Task { [weak self] in
      guard let self else { return }
      // An explicit search sends only the person's query and public results.
      // Private records and agent-generated search words never enter this path.
      await self.executeWebResearch(reportID, summarize: true)
      guard self.aiChatRequestID == requestID, !Task.isCancelled else { return }
      defer {
        self.isAIChatResponding = false
        self.aiChatRequestID = nil
        self.aiChatTask = nil
      }
      guard let report = self.webResearch(id: reportID) else { return }
      let text = report.answer.isEmpty ? (report.sources.isEmpty ? report.error ?? "検索結果を取得できませんでした。" :
        "Webから\(report.sources.count)件の情報を取得しました。\n\n\(report.error ?? "AIの回答は生成されていません。")\n出典から取得内容を確認できます。") : report.answer
      self.updateAgentMessage(reply.id) {
        $0.text = text
        $0.isThinking = false
        $0.searchFinished = true
        $0.finishedAt = .now
        if let engine = report.engineLabel {
          $0.details = AIAnswerDetails(scopeLabel: "Web検索", engineLabel: engine, modelLabel: report.modelLabel,
            sourceCount: report.sentSourceIDs?.count ?? 0, generatedAt: .now)
        }
      }
      self.saveAIExchange(question: question, answer: text, scopeLabel: "Web検索",
        engineLabel: report.engineLabel ?? "Web検索（AI回答なし）", modelLabel: report.modelLabel,
        webResearchReportID: reportID)
    }
    return true
  }
}
