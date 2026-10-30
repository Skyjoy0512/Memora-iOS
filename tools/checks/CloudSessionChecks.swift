import Foundation

@main
struct CloudSessionChecks {
  typealias Wire = CloudSessionFixtureProtocol
  typealias Response = CloudSessionFixtureResponse

  @MainActor static func main() async throws {
    try await CloudSummaryTransportChecks.run()
    if ProcessInfo.processInfo.environment["MEMORA_REALTIME_SUMMARY_CHECKS"] == "1" {
      try await SlowSummaryHTTPChecks.run()
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("memora-cloud-fixture-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for provider in [LLMProvider.openAI, .anthropic] {
      for streaming in [false, true] {
        try await personMailScenario(root: root, provider: provider, streaming: streaming)
        try await rejectsUnsafeTurns(provider: provider, streaming: streaming)
      }
      try await jsonFallback(provider: provider)
      try await suspendedRevocation(root: root, provider: provider)
      try await approvalBoundaryChecks(root: root, provider: provider)
      try await cancelledTransport(provider: provider)
      try await preflightBudgets(provider: provider)
    }
    try await httpFailures()
    try await schemaAndSelectionChecks()
    try await exhaustedBudget()
    print("CloudSessionChecks: passed (production CloudAgentSession + URLSession/JSON/SSE + registry/policy + conversation loop + person/mail/document/SQLite; both API formats, no network/keys/paid API)")
  }

  @MainActor static func configuration() -> URLSessionConfiguration {
    let value = URLSessionConfiguration.ephemeral
    value.protocolClasses = [Wire.self]
    return value
  }

  @MainActor static func session(_ provider: LLMProvider, tools: [AgentTool] = [.readPerson, .draftEmail], budget: AgentRunBudget? = nil) -> CloudAgentSession {
    let model = provider.usesAnthropicAPI ? "claude-sonnet-5" : "gpt-6-sol"
    return CloudAgentSession(llm: LLMSelection(provider: provider, modelID: model), system: "架空データだけの検証", tools: tools,
      runBudget: budget, sessionConfiguration: configuration())!
  }

  @MainActor static func next(_ session: CloudAgentSession, streaming: Bool) async throws -> AgentTurn {
    if streaming { return try await session.next(onText: { _ in }) }
    return try await session.next()
  }

  @MainActor static func fixture(root: URL) throws -> (MemoraModel, Person, URL) {
    let storeURL = root.appendingPathComponent(UUID().uuidString + ".sqlite")
    let model = try MemoraModel(storeURL: storeURL)
    var privacy = RecordPrivacy(classification: .personal); privacy.allowsCloudAI = true
    let person = Person(id: UUID(), name: "架空の田中", note: "相談の窓口", contactIdentifier: nil, privacy: privacy)
    model.people = [person, Person(id: UUID(), name: person.name, note: "非公開の別人", contactIdentifier: nil)]
    model.tasks = [MemoraTask(id: UUID(), title: "概算の確認", isCompleted: false,
      relationships: TaskRelationships(assigneePersonID: person.id), privacy: privacy)]
    model.lifeLogEntries = [LifeLogEntry(id: UUID(), createdAt: .now, title: "架空の相談", summary: "次回に確認", source: .iphone,
      privacy: privacy, personIDs: [person.id])]
    model.meetings = [Meeting(title: "非公開の会議", participantIDs: [person.id], privacy: .init(classification: .personal))]
    model.message.cloudProvenance = model.newCloudProvenance(references: [])
    model.message.cloudAuthorizationTargets = []
    let tools: [AgentTool] = [.readPerson, .draftEmail, .createDocument, .searchEmail]
    for tool in tools {
      _ = model.fixtureRegistry.register(AIToolDefinition(id: "memora:" + tool.rawValue, name: tool.rawValue, summary: tool.summary,
        inputSchema: try JSONSerialization.data(withJSONObject: tool.inputSchema), provider: .memora, requiredPermissions: [],
        risk: tool.needsApproval ? .write : .read, isAvailable: !tool.needsGmail, isEnabled: true))
    }
    model.agentPluginPolicies[model.message.id] = AIPluginExecutionPolicy(pluginIDs: ["skill:email-draft"],
      toolIDs: ["memora:read_person", "memora:draft_email"], recordIDs: [], limitsRecordReads: false)
    return (model, person, storeURL)
  }

  @MainActor static func personMailScenario(root: URL, provider: LLMProvider, streaming: Bool) async throws {
    let (model, person, storeURL) = try fixture(root: root)
    let read = AgentToolCall(id: "person-1", name: "read_person", arguments: ["person_id": person.id.uuidString, "name": ""])
    let marker = AnswerSourceCitation.marker(for: .record(.task(model.tasks[0].id)))
    let draft = AgentToolCall(id: "draft-1", name: "draft_email", arguments: ["to": [], "subject": "ご相談の確認", "body": "概算を確認します。" + marker])
    let text = "概算の確認が未完了です。" + marker
    func reply(calls: [AgentToolCall], text: String = "") throws -> Wire.Reply {
      try streaming ? Response.sse(provider: provider, calls: calls, text: text) : Response.json(provider: provider, calls: calls, text: text)
    }
    Wire.state.reset(try [reply(calls: [read]), reply(calls: [draft]), reply(calls: [], text: text)])
    let session = session(provider)
    session.addUserMessage("この人との相談をもとに、メールの下書きを作って")
    var outcomes: [AgentToolOutcome] = []
    var approvals = 0
    model.approvalAction = { approvals += 1; await Task.yield() }
    let result = await AgentConversationLoop.run(isAuthorized: { model.isCloudSessionAuthorized(model.message.id) },
      next: { try await next(session, streaming: streaming) }, checkExecution: { try session.runBudget.check() }, execute: { call in
        guard model.pluginCallIsPermitted(call, messageID: model.message.id) else { return .init(text: "拒否", isError: true) }
        switch call.tool {
        case .readPerson: return model.readPersonTool(call, messageID: model.message.id, compact: false, purpose: .cloudAI)
        case .draftEmail: return await model.draftEmailTool(call, messageID: model.message.id)
        default: preconditionFailure("Tool selection escaped")
        }
      }, accept: { _, batch in outcomes += batch.map(\.outcome); if !batch.isEmpty { session.addToolResults(batch) } })
    precondition(result.text == text && outcomes.count == 2 && outcomes.allSatisfy { !$0.isError })
    precondition(approvals == 1 && model.mailDrafts.count == 1)
    precondition(model.mailDrafts[0].recipients.isEmpty && model.mailDrafts[0].status == .draft && !model.mailDrafts[0].body.contains(marker))
    precondition(model.mailDrafts[0].provenance?.records.count == 3)
    model.message.text = text
    let document = model.document(from: model.message)
    precondition(model.addDocument(document))
    let reopened = LocalStore(fileURL: storeURL); try reopened.prepare()
    guard case .data(let documents) = reopened.readOutcome("documents"), case .data(let drafts) = reopened.readOutcome("memora.mailDrafts.v1") else { preconditionFailure() }
    let savedDrafts = try JSONDecoder().decode([MailDraft].self, from: drafts)
    let savedDocuments = try JSONDecoder().decode([MemoraDocument].self, from: documents)
    precondition(savedDrafts[0].provenance == model.mailDrafts[0].provenance)
    precondition(savedDocuments[0].markdown.contains("memora://source/task/"))
    let requests = Wire.state.requests
    for request in requests { try validateRequest(request, provider: provider, streaming: streaming) }
    let followup = try body(requests[1])
    let followupText = String(decoding: try JSONSerialization.data(withJSONObject: followup), as: UTF8.self)
    precondition(followupText.contains("person-1") && followupText.contains("概算の確認"))
    precondition(!followupText.contains("非公開の別人") && !followupText.contains("非公開の会議"))
    let messages = followup["messages"] as! [[String: Any]]
    let assistant = messages.first { $0["role"] as? String == "assistant" }!
    if provider.usesAnthropicAPI {
      let content = assistant["content"] as! [[String: Any]]
      precondition(content.first?["signature"] as? String == "fixture-signature")
      let results = messages.last?["content"] as! [[String: Any]]
      precondition(results.first?["tool_use_id"] as? String == read.id && results.first?["is_error"] as? Bool == false)
    } else {
      precondition(assistant["reasoning_content"] as? String == "架空の検討")
      precondition(messages.last?["role"] as? String == "tool" && messages.last?["tool_call_id"] as? String == read.id)
    }
    precondition(session.runBudget.requestCount == 3 && session.runBudget.chargedOutputTokens == 36)
    Wire.state.assertConsumed(3)
  }

  static func body(_ request: URLRequest) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
  }

  static func validateRequest(_ request: URLRequest, provider: LLMProvider, streaming: Bool) throws {
    precondition(request.httpMethod == "POST" && request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    precondition(request.url?.host == (provider.usesAnthropicAPI ? "api.anthropic.com" : "api.openai.com"))
    precondition(request.url?.path == (provider.usesAnthropicAPI ? "/v1/messages" : "/v1/chat/completions"))
    if provider.usesAnthropicAPI {
      precondition(request.value(forHTTPHeaderField: "x-api-key") == "offline-fixture-key")
      precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
      precondition(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    } else {
      precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer offline-fixture-key")
      precondition(request.value(forHTTPHeaderField: "x-api-key") == nil)
    }
    let object = try body(request)
    let definitions = object["tools"] as! [[String: Any]]
    let names = definitions.map { provider.usesAnthropicAPI ? $0["name"] as! String : ($0["function"] as! [String: Any])["name"] as! String }
    precondition(Set(names) == ["read_person", "draft_email"])
    precondition(object[provider.usesAnthropicAPI ? "max_tokens" : "max_completion_tokens"] as? Int == 16_000)
    precondition((object["stream"] as? Bool == true) == streaming)
    if streaming { precondition(request.value(forHTTPHeaderField: "Accept") == "text/event-stream") }
    if !provider.usesAnthropicAPI {
      precondition(object["reasoning_effort"] as? String == "none")
      precondition(((object["stream_options"] as? [String: Any])?["include_usage"] as? Bool == true) == streaming)
    }
  }

  @MainActor static func rejectsUnsafeTurns(provider: LLMProvider, streaming: Bool) async throws {
    let call = AgentToolCall(id: "same-call", name: "draft_email", arguments: ["body": "架空本文", "subject": "確認"])
    let malformed = try streaming ? Response.sse(provider: provider, calls: [call], terminated: false) :
      Response.json(provider: provider, calls: [call], finish: provider.usesAnthropicAPI ? "max_tokens" : "length")
    Wire.state.reset([malformed])
    let session = session(provider)
    session.addUserMessage("架空の依頼")
    let result = await AgentConversationLoop.run(isAuthorized: { true }, next: { try await next(session, streaming: streaming) },
      execute: { _ in preconditionFailure("Incomplete call executed") }, accept: { _, _ in preconditionFailure("Incomplete turn accepted") })
    guard case .failure(let reason) = result, [AIAnswerFailure.connectionLost, .executionLimit].contains(reason) else { preconditionFailure() }
    Wire.state.assertConsumed(1)
    func valid() throws -> Wire.Reply { try streaming ? Response.sse(provider: provider, calls: [call]) : Response.json(provider: provider, calls: [call]) }
    Wire.state.reset(try [valid(), valid()])
    let replaySession = self.session(provider)
    var executions = 0
    let replay = await AgentConversationLoop.run(isAuthorized: { true }, next: { try await next(replaySession, streaming: streaming) },
      execute: { _ in executions += 1; return .init(text: "拒否済み") }, accept: { _, batch in replaySession.addToolResults(batch) })
    guard case .failure(.server) = replay else { preconditionFailure("Replayed ID accepted") }
    precondition(executions == 1)
    Wire.state.assertConsumed(2)
  }

  @MainActor static func jsonFallback(provider: LLMProvider) async throws {
    Wire.state.reset([try Response.json(provider: provider, text: "日本語👨‍👩‍👧‍👦")])
    let session = session(provider)
    let turn = try await session.next(onText: { _ in })
    precondition(turn.text == "日本語👨‍👩‍👧‍👦")
    Wire.state.assertConsumed(1)
  }

  @MainActor static func suspendedRevocation(root: URL, provider: LLMProvider) async throws {
    for change in 0..<5 {
      let (model, person, _) = try fixture(root: root)
      model.recordCloudReads([.person(person.id)], messageID: model.message.id)
      var reply = try Response.sse(provider: provider, calls: [.init(id: "late", name: "draft_email", arguments: ["subject": "確認", "body": "本文"])])
      reply.isSuspended = true
      Wire.state.reset([reply])
      let session = session(provider)
      let run = Task { @MainActor in
        await AgentConversationLoop.run(isAuthorized: { model.isCloudSessionAuthorized(model.message.id) }, next: { try await session.next(onText: { _ in }) },
          execute: { _ in preconditionFailure("Stale reply executed") }, accept: { _, _ in preconditionFailure("Stale reply accepted") })
      }
      await waitForSuspension()
      switch change {
      case 0: model.people[0].privacy.allowsCloudAI = false
      case 1: model.people[0].note = "参照後に編集"
      case 2: model.currentTeamID = "different-workspace"
      case 3: model.isRestoring = true
      default: model.people.removeFirst()
      }
      Wire.state.release()
      let result = await run.value
      guard case .failure(.contextChanged) = result else { preconditionFailure("Stale reply kept") }
      precondition(model.mailDrafts.isEmpty)
      Wire.state.assertConsumed(1)
    }
  }

  @MainActor static func cancelledTransport(provider: LLMProvider) async throws {
    var reply = try Response.sse(provider: provider, text: "停止後の回答")
    reply.isSuspended = true
    Wire.state.reset([reply])
    let session = session(provider)
    let run = Task { @MainActor in
      await AgentConversationLoop.run(isAuthorized: { true }, next: { try await session.next(onText: { _ in preconditionFailure("Cancelled text published") }) },
        execute: { _ in preconditionFailure() }, accept: { _, _ in preconditionFailure("Cancelled turn accepted") })
    }
    await waitForSuspension()
    run.cancel()
    let result = await run.value
    guard case .failure(.cancelled) = result else { preconditionFailure("Transport cancellation lost") }
    Wire.state.release()
    Wire.state.assertConsumed(1)
  }

  @MainActor static func approvalBoundaryChecks(root: URL, provider: LLMProvider) async throws {
    for change in 0..<6 {
      let (model, person, _) = try fixture(root: root)
      let messageID = model.message.id
      let read = AgentToolCall(id: "approval-person", name: "read_person", arguments: ["name": "", "person_id": person.id.uuidString])
      let draft = AgentToolCall(id: "approval-draft", name: "draft_email", arguments: ["subject": "確認", "body": "本文", "to": []])
      let invalidatesContext = change == 3 || change == 4
      var replies = try [Response.sse(provider: provider, calls: [read]), Response.sse(provider: provider, calls: [draft])]
      if !invalidatesContext { replies.append(try Response.json(provider: provider, text: "保存していません。")) }
      Wire.state.reset(replies)
      let session = session(provider)
      var approvals = 0
      var outcomes: [AgentToolOutcome] = []
      model.approvalAction = {
        approvals += 1
        await Task.yield()
        switch change {
        case 0: model.approves = false
        case 1: model.fixtureRegistry.tools["memora:draft_email"]?.isEnabled = false
        case 2: model.agentPluginPolicies[messageID]?.toolIDs.remove("memora:draft_email")
        case 3: model.currentTeamID = "workspace-after-approval"
        case 4: model.tasks[0].title = "承認待ちに編集"
        default: model.rejectWrites = true
        }
      }
      let result = await AgentConversationLoop.run(isAuthorized: { model.isCloudSessionAuthorized(messageID) },
        next: { try await session.next(onText: { _ in }) }, execute: { call in
          guard model.pluginCallIsPermitted(call, messageID: messageID) else { preconditionFailure("Call rejected before approval fixture") }
          if call.tool == .readPerson { return model.readPersonTool(call, messageID: messageID, compact: false, purpose: .cloudAI) }
          let outcome = await model.draftEmailTool(call, messageID: messageID)
          outcomes.append(outcome)
          return outcome
        }, accept: { _, batch in if !batch.isEmpty { session.addToolResults(batch) } })
      precondition(approvals == 1 && model.mailDrafts.isEmpty && model.pendingMailDraft == nil && outcomes.count == 1)
      if invalidatesContext {
        guard case .failure(.contextChanged) = result else { preconditionFailure("Changed approval context reused") }
      } else {
        precondition(result.text == "保存していません。" && outcomes[0].isError == (change != 0))
        if provider.usesAnthropicAPI {
          let messages = try body(Wire.state.requests[2])["messages"] as! [[String: Any]]
          let results = messages.last?["content"] as! [[String: Any]]
          precondition(results[0]["tool_use_id"] as? String == draft.id && results[0]["is_error"] as? Bool == (change != 0))
        }
      }
      Wire.state.assertConsumed(invalidatesContext ? 2 : 3)
    }
  }

  @MainActor static func waitForSuspension() async {
    let start = ContinuousClock.now
    while !Wire.state.isSuspended {
      precondition(start.duration(to: .now) < .seconds(5), "URLProtocol did not suspend")
      await Task.yield()
    }
  }

  @MainActor static func httpFailures() async throws {
    for (status, reason) in [(401, AIAnswerFailure.unauthorized), (402, .outOfCredits), (403, .unauthorized),
      (404, .modelUnavailable), (429, .rateLimited), (503, .providerUnavailable)] {
      var response = try Response.json(provider: .openAI)
      response.status = status
      Wire.state.reset([response])
      do { _ = try await session(.openAI).next(onText: { _ in }); preconditionFailure("HTTP failure accepted") }
      catch let error as AIAnswerFailure { precondition(error == reason) }
      Wire.state.assertConsumed(1)
    }
    for (code, reason) in [(URLError.Code.timedOut, AIAnswerFailure.timedOut), (.networkConnectionLost, .connectionLost)] {
      Wire.state.reset([.init(data: Data(), error: URLError(code))])
      do { _ = try await session(.openAI).next(); preconditionFailure("Transport failure accepted") }
      catch let error as AIAnswerFailure { precondition(error == reason) }
      Wire.state.assertConsumed(1)
    }
  }

  @MainActor static func schemaAndSelectionChecks() async throws {
    let valid = AgentToolCall(id: "decline", name: "draft_email", arguments: ["subject": "件名", "body": "本文"])
    let disallowed = AgentToolCall(id: "unselected", name: "create_document", arguments: ["title": "提案", "markdown": "本文"])
    let wrongSchema = AgentToolCall(id: "invalid", name: "draft_email", arguments: ["subject": 42, "body": "本文"])
    let disconnected = AgentToolCall(id: "gmail", name: "search_email", arguments: ["query": "架空"])
    var registry = AIToolRegistry()
    for tool in [AgentTool.draftEmail, .createDocument] {
      _ = registry.register(.init(id: "memora:" + tool.rawValue, name: tool.rawValue, summary: "", inputSchema: try JSONSerialization.data(withJSONObject: tool.inputSchema),
        provider: .memora, requiredPermissions: [], risk: .write, isAvailable: true, isEnabled: true))
    }
    let policy = AIPluginExecutionPolicy(pluginIDs: ["skill:email-draft"], toolIDs: ["memora:draft_email"], recordIDs: [], limitsRecordReads: false)
    Wire.state.reset([try Response.sse(provider: .openAI, calls: [disallowed, wrongSchema, disconnected, valid]), try Response.json(provider: .openAI)])
    let session = session(.openAI, tools: [.draftEmail])
    var rejected = 0, approved = 0
    let result = await AgentConversationLoop.run(isAuthorized: { true }, next: { try await session.next(onText: { _ in }) }, execute: { call in
      guard registry.permits(call.name, arguments: call.arguments, policy: policy) else { rejected += 1; return .init(text: "範囲またはスキーマを拒否", isError: true) }
      approved += 1
      return .init(text: "利用者が保存を承認しませんでした。")
    }, accept: { _, batch in if !batch.isEmpty { session.addToolResults(batch) } })
    precondition(result.text == "完了" && rejected == 3 && approved == 1)
    let followup = try body(Wire.state.requests[1])["messages"] as! [[String: Any]]
    let results = followup.filter { $0["role"] as? String == "tool" }
    precondition(results.map { $0["tool_call_id"] as! String } == [disallowed.id, wrongSchema.id, disconnected.id, valid.id])
    precondition(!AgentTool.offered.contains(.searchEmail))
    Wire.state.assertConsumed(2)
  }

  @MainActor static func exhaustedBudget() async throws {
    var response = try Response.json(provider: .openAI)
    var object = try JSONSerialization.jsonObject(with: response.data) as! [String: Any]
    object.removeValue(forKey: "usage")
    response.data = try JSONSerialization.data(withJSONObject: object)
    Wire.state.reset(Array(repeating: response, count: 4))
    let budget = AgentRunBudget(output: AgentOutputBudget(maximumTokens: 64_000))
    let session = session(.openAI, budget: budget)
    for _ in 0..<4 { _ = try await session.next() }
    do { _ = try await session.next(); preconditionFailure("Fifth unmetered request sent") }
    catch AIAnswerFailure.executionLimit {}
    precondition(budget.requestCount == 4 && budget.chargedOutputTokens == 64_000)
    Wire.state.assertConsumed(4)
  }

  @MainActor static func preflightBudgets(provider: LLMProvider) async throws {
    let model = provider.usesAnthropicAPI ? "claude-sonnet-5" : "gpt-6-sol"
    let key = ModelCapabilityOverrides.key(provider: provider, modelID: model)
    let small = ModelCapabilityOverride(contextWindowTokens: 4_096, maximumOutputTokens: 256, maximumRequestBytes: 65_536)
    func make(system: String = "検査", override: ModelCapabilityOverride? = nil,
              task: ContextTaskKind = .agent) -> CloudAgentSession {
      CloudAgentSession(llm: .init(provider: provider, modelID: model), system: system, tools: [],
        sessionConfiguration: configuration(), contextTask: task, capabilityOverrides: [key: override ?? small])!
    }
    for scenario in 0..<4 {
      Wire.state.reset([])
      let session: CloudAgentSession
      switch scenario {
      case 0: session = make(system: String(repeating: "会", count: 4_000))
      case 1:
        session = make(); session.addUserMessage(String(repeating: "会", count: 4_000))
      case 2:
        session = make()
        session.externalTools = [.init(serverID: UUID(), serverName: "fixture", name: "read", summary: String(repeating: "会", count: 4_000),
          inputSchema: Data(#"{"type":"object"}"#.utf8), isReadOnly: true)]
      default:
        // Characters fit the large window, but Japanese UTF-8 exceeds 64 KiB.
        session = make(system: String(repeating: "会", count: 24_000),
          override: .init(contextWindowTokens: 400_000, maximumOutputTokens: 256, maximumRequestBytes: 65_536))
      }
      do { _ = try await session.next(); preconditionFailure("Oversize request reached transport") }
      catch AIAnswerFailure.executionLimit {}
      precondition(session.runBudget.requestCount == 0 && session.runBudget.chargedOutputTokens == 0)
      Wire.state.assertConsumed(0)
    }

    Wire.state.reset([try Response.json(provider: provider)])
    let tiny = make()
    tiny.addUserMessage("短い依頼")
    _ = try await tiny.next()
    let outputField = provider.usesAnthropicAPI ? "max_tokens" : "max_completion_tokens"
    let tinyBody = try body(Wire.state.requests[0])
    precondition(tinyBody[outputField] as? Int == 256)
    Wire.state.assertConsumed(1)

    // Provider thinking is retained, counted, and never truncated as if it
    // were an expendable tool result. The next request must stop locally.
    var thinkingReply = try Response.json(provider: provider)
    var thinkingObject = try JSONSerialization.jsonObject(with: thinkingReply.data) as! [String: Any]
    if provider.usesAnthropicAPI {
      var content = thinkingObject["content"] as! [[String: Any]]
      content[0]["thinking"] = String(repeating: "会", count: 4_000)
      thinkingObject["content"] = content
    } else {
      var choices = thinkingObject["choices"] as! [[String: Any]]
      var message = choices[0]["message"] as! [String: Any]
      message["reasoning_content"] = String(repeating: "会", count: 4_000)
      choices[0]["message"] = message; thinkingObject["choices"] = choices
    }
    thinkingReply.data = try JSONSerialization.data(withJSONObject: thinkingObject)
    Wire.state.reset([thinkingReply])
    let growing = make()
    growing.addUserMessage("依頼")
    _ = try await growing.next()
    do { _ = try await growing.next(); preconditionFailure("Protected recent context escaped its window") }
    catch AIAnswerFailure.executionLimit {}
    precondition(growing.runBudget.requestCount == 1 && growing.runBudget.chargedOutputTokens == 12)
    Wire.state.assertConsumed(1)

    Wire.state.reset([try Response.json(provider: provider)])
    let presentation = CloudAgentSession(llm: .init(provider: provider, modelID: model), system: "資料検査", tools: [],
      sessionConfiguration: configuration(), contextTask: .presentation, capabilityOverrides: [:])!
    presentation.addUserMessage("資料を作る")
    _ = try await presentation.next()
    let presentationBody = try body(Wire.state.requests[0])
    precondition(presentationBody[outputField] as? Int == 32_000)
    Wire.state.assertConsumed(1)
    print("Preflight budgets passed: \(provider), system/schemas/user/byte limits before transport, 256-token cap, recent-turn refusal, presentation output reservation")
  }
}
