import Foundation

extension MemoraModel {
  func saveToNotionTool(_ call: AgentToolCall, messageID: UUID, scope: AIChatScope,
                       environment: NotionSaveEnvironment) async -> AgentToolOutcome {
    guard !agentBlockedExternalTools[messageID, default: []].contains(call.name),
          call.tool == .saveToNotion, let id = UUID(uuidString: call.string("meeting_id")),
          agentPluginPolicies[messageID].map({ !$0.limitsRecordReads || $0.recordIDs.contains(id) }) ?? true,
          let export = NotionExportContext(in: self, meetingID: id, scope: scope) else {
      return AgentToolOutcome(text: RecordAccessPolicy.refusal, isError: true)
    }
    guard let configuration = environment.configuration() else {
      return AgentToolOutcome(text: "Notionが連携されていません。設定の「Notion」で連携するよう伝えてください。", isError: true)
    }
    recordCloudReads([.meeting(id)] + export.tasks.map { .task($0.id) }, messageID: messageID)
    guard let context = NotionAgentExecutionContext(in: self, export: export, call: call, messageID: messageID) else {
      return AgentToolOutcome(text: AIAnswerFailure.contextChanged.message, isError: true)
    }
    let stepID = beginAgentStep(AgentStep(icon: AgentTool.saveToNotion.icon, title: "Notionに保存", detail: "確認待ち"), on: messageID)
    let approved = await requestAgentApproval(AgentApproval(messageID: messageID, icon: AgentTool.saveToNotion.icon,
      title: "Notionに保存", lines: [export.meeting.displayTitle, "この記録と送信を許可した関連タスクをNotionへ送ります。", "外部処理の料金は未確認です。今回の保存だけを許可します。"], confirmTitle: "保存"))
    guard approved, context.isCurrent(in: self), environment.configuration() == configuration else {
      if context.ownsMessage(in: self) {
        agentBlockedExternalTools[messageID, default: []].insert(call.name)
        finishAgentStep(stepID, on: messageID, state: .declined, detail: "送信を止めました")
      }
      return AgentToolOutcome(text: "承認または参照範囲・接続設定が変わったため、送信を止めました。自動再実行はしません。", isError: approved)
    }
    finishAgentStep(stepID, on: messageID, state: .running, detail: "")
    var dataChange = AgentToolOutcome.DataChange.none
    var trackedEnvironment = environment
    trackedEnvironment.transport = { request in
      if request.httpMethod == "POST" || request.httpMethod == "PATCH" { dataChange = .unconfirmed }
      return try await environment.transport(request)
    }
    do {
      let outcome = try await saveNotionExport(export, configuration: configuration, environment: trackedEnvironment,
        isAuthorized: { [weak self] in self.map { context.isCurrent(in: $0) } ?? false })
      dataChange = .committed
      guard context.isCurrent(in: self), environment.configuration() == configuration else {
        if context.ownsMessage(in: self) {
          agentBlockedExternalTools[messageID, default: []].insert(call.name)
          finishAgentStep(stepID, on: messageID, state: .failed,
            detail: "保存先で結果を確認してください。自動再作成はしません。" + (outcome.pageURL.map { " ページ: " + $0.absoluteString } ?? ""))
        }
        return AgentToolOutcome(text: AIAnswerFailure.contextChanged.message, isError: true, dataChange: dataChange)
      }
      finishAgentStep(stepID, on: messageID, state: .done, detail: export.meeting.displayTitle)
      return AgentToolOutcome(text: "Notionに保存しました。\(outcome.pageURL?.absoluteString ?? "")", dataChange: .committed)
    } catch {
      let partial = error as? NotionService.PartialPageFailure
      if partial != nil { dataChange = .committed }
      if context.ownsMessage(in: self) {
        agentBlockedExternalTools[messageID, default: []].insert(call.name)
        // Keep a known page for the original person's local trace, not a new
        // conversation/model request. It is not a durable cross-workspace receipt.
        let detail = partial.map { $0.message + ($0.pageURL.map { " ページ: " + $0.absoluteString } ?? "") }
        finishAgentStep(stepID, on: messageID, state: .failed, detail: detail ?? "保存できませんでした")
      }
      guard context.isCurrent(in: self), environment.configuration() == configuration else {
        return AgentToolOutcome(text: AIAnswerFailure.contextChanged.message + "開始済みの送信は取り消せません。Notionで確認してください。自動再作成はしません。", isError: true, dataChange: dataChange)
      }
      if let partial {
        return AgentToolOutcome(text: partial.message + (partial.pageURL.map { " ページ: " + $0.absoluteString } ?? ""), isError: true, dataChange: dataChange)
      }
      if case NotionService.Failure.http(let code) = error {
        return AgentToolOutcome(text: ExternalToolFailure.http(code).localizedDescription, isError: true, dataChange: dataChange)
      }
      return AgentToolOutcome(text: "Notionへの保存結果を確認できませんでした。サービス側でページを確認してください。自動再作成はしません。", isError: true, dataChange: dataChange)
    }
  }
}
