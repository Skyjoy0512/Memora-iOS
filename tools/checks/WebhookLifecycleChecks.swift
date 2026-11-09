import Foundation
import Synchronization

@main @MainActor
struct WebhookLifecycleChecks {
  static func main() async throws {
    var record = Meeting(id: UUID(), title: "private record", createdAt: .now, duration: 2,
      source: .recording, status: .ready, summary: "private summary", keyPoints: [], decisions: [],
      openQuestions: [], transcript: [], spaceID: nil, audioURL: nil)
    record.privacy = RecordPrivacy(classification: .general, allowsAutomaticWebhook: true)
    let task = MemoraTask(id: UUID(), title: "private task", meetingID: record.id,
      assignee: nil, dueDate: nil, isCompleted: false)
    let endpoint = WebhookEndpoint(id: UUID(), name: "fixture", format: .json)
    func model() -> MemoraModel {
      let model = MemoraModel()
      model.meetings = [record]; model.tasks = [task]
      precondition(model.saveWebhook(endpoint, url: "https://example.invalid/original"))
      return model
    }
    let cancelledModel = model()
    let cancelledEnqueue = Task { cancelledModel.deliverSummaryToWebhooks(record.id) }
    cancelledEnqueue.cancel()
    await cancelledEnqueue.value
    for _ in 0..<20 { await Task.yield() }
    precondition(cancelledModel.webhookDeliveries.isEmpty && WebhookTransportFixture.requests.isEmpty)
    for inFlight in [false, true] {
      for change in 0..<10 {
        WebhookTransportFixture.reset()
        let model = model()
        model.deliverSummaryToWebhooks(record.id)
        if inFlight { await WebhookTransportFixture.entered(1) }
        switch change {
        case 0:
          model.webhookEndpoints[0].isEnabled = false
          model.webhookEndpoints[0].isEnabled = true
        case 1: model.deleteWebhook(endpoint.id)
        case 2: precondition(model.saveWebhook(endpoint, url: "https://example.invalid/replaced"))
        case 3: model.meetings[0].summary = "edited after enqueue"
        case 4:
          model.meetings[0].privacy.allowsAutomaticWebhook = false
          model.meetings[0].privacy.allowsAutomaticWebhook = true
        case 5: model.tasks[0].title = "edited task"
        case 6: model.currentTeamID = "team"
        case 7: model.isRestoring = true
        case 8: model.isStoreProtected = true
        default: model.tasks[0].privacy = RecordPrivacy(classification: .general, allowsAutomaticWebhook: false)
        }
        if inFlight { WebhookTransportFixture.finish(0, success: true) }
        for _ in 0..<20 { await Task.yield() }
        precondition(model.webhookDeliveries.isEmpty && model.webhookResults[endpoint.id] == nil)
        precondition(WebhookTransportFixture.requests.count == (inFlight ? 1 : 0))
      }
    }
    WebhookTransportFixture.reset()
    let replacement = model()
    replacement.testWebhook(endpoint)
    await WebhookTransportFixture.entered(1)
    let testPayload = String(decoding: WebhookTransportFixture.requests[0].payload, as: UTF8.self)
    precondition(testPayload.contains("テスト送信") && !testPayload.contains("private record"))
    replacement.testWebhook(endpoint)
    await WebhookTransportFixture.entered(2)
    WebhookTransportFixture.finish(1, success: true)
    for _ in 0..<20 { await Task.yield() }
    precondition(replacement.webhookResults[endpoint.id]?.succeeded == true)
    WebhookTransportFixture.finish(0, success: false)
    for _ in 0..<20 { await Task.yield() }
    precondition(replacement.webhookResults[endpoint.id]?.succeeded == true && replacement.webhookDeliveries.isEmpty)
    try await transportChecks()
    print("PASS: production webhook lifecycle and HTTP; 20 queued/in-flight revocation/configuration/workspace/content races, OFF/ON refusal, replacement result isolation, test-data isolation, HTTPS/redirect and payload/response limits. Model/keychain/URLProtocol are fixtures; no external requests.")
  }

  static func transportChecks() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WebhookURLProtocol.self]
    let url = URL(string: "https://example.invalid/hook")!
    let body = Data("fixture".utf8)
    WebhookURLProtocol.configure()
    let denied = await WebhookDelivery.send(body, to: url, configuration: configuration) { false }
    precondition(!denied.succeeded && WebhookURLProtocol.count == 0)
    let insecure = await WebhookDelivery.send(body, to: URL(string: "http://example.invalid")!, configuration: configuration) { true }
    precondition(!insecure.succeeded && WebhookURLProtocol.count == 0)
    let tooBig = await WebhookDelivery.send(Data(repeating: 1, count: WebhookDelivery.maximumPayloadBytes + 1), to: url, configuration: configuration) { true }
    precondition(!tooBig.succeeded && WebhookURLProtocol.count == 0)
    let success = await WebhookDelivery.send(body, to: url, configuration: configuration) { true }
    precondition(success.succeeded && WebhookURLProtocol.count == 1)
    WebhookURLProtocol.configure(declaredLength: WebhookDelivery.maximumResponseBytes + 1)
    let declared = await WebhookDelivery.send(body, to: url, configuration: configuration) { true }
    precondition(!declared.succeeded && declared.message.contains("大きすぎる"))
    WebhookURLProtocol.configure(bodySize: WebhookDelivery.maximumResponseBytes + 1)
    let streamed = await WebhookDelivery.send(body, to: url, configuration: configuration) { true }
    precondition(!streamed.succeeded && streamed.message.contains("大きすぎる"))
    WebhookURLProtocol.configure(status: 302)
    let redirect = await WebhookDelivery.send(body, to: url, configuration: configuration) { true }
    precondition(!redirect.succeeded && WebhookURLProtocol.count == 1)
    var follow: URLRequest? = URLRequest(url: url)
    let session = URLSession(configuration: configuration)
    WebhookRedirectPolicy().urlSession(session, task: session.dataTask(with: url),
      willPerformHTTPRedirection: HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!,
      newRequest: URLRequest(url: URL(string: "https://example.invalid/other")!)) { follow = $0 }
    session.invalidateAndCancel()
    precondition(follow == nil)
    WebhookURLProtocol.configure(hold: true)
    let operation = Task { await WebhookDelivery.send(body, to: url, configuration: configuration) { true } }
    for _ in 0..<10000 { if WebhookURLProtocol.count > 0 { break }; await Task.yield() }
    precondition(WebhookURLProtocol.count == 1)
    operation.cancel()
    let cancelled = await operation.value
    precondition(!cancelled.succeeded)
  }
}

@MainActor final class MemoraModel {
  var meetings: [Meeting] = [] { didSet { invalidatePendingWebhookDeliveries() } }
  var tasks: [MemoraTask] = [] { didSet { invalidatePendingWebhookDeliveries() } }
  var currentTeamID: String? { didSet { invalidatePendingWebhookDeliveries() } }
  var aiWorkspaceGeneration = UUID()
  var isRestoring = false { didSet { invalidatePendingWebhookDeliveries() } }
  var isStoreProtected = false { didSet { invalidatePendingWebhookDeliveries() } }
  var webhookEndpoints: [WebhookEndpoint] = [] { didSet { invalidatePendingWebhookDeliveries() } }
  var webhookResults: [UUID: WebhookResult] = [:]
  var webhookDeliveries: [UUID: WebhookDeliveryJob] = [:]
  var latestWebhookDeliveryIDs: [UUID: UUID] = [:]
  func meeting(id: UUID) -> Meeting? { meetings.first { $0.id == id } }
  func tasks(forMeeting id: UUID) -> [MemoraTask] { tasks.filter { $0.meetingID == id } }
  func allowsRecordAccess(_ id: UUID, purpose: RecordAccessPolicy.Purpose) -> Bool {
    meeting(id: id).map { RecordAccessPolicy.allows($0.privacy, purpose: purpose) } ?? false
  }
  func allowsTaskAccess(_ task: MemoraTask, purpose: RecordAccessPolicy.Purpose) -> Bool {
    RecordAccessPolicy.allowsRelated(task.privacy, parentID: task.meetingID,
      parentPrivacy: task.meetingID.flatMap { meeting(id: $0)?.privacy }, purpose: purpose, inheritsParent: true)
  }
}
@MainActor enum KeychainStore {
  static var values: [String: String] = [:]
  static func string(forKey key: String) -> String? { values[key] }
  @discardableResult static func set(_ value: String?, forKey key: String) -> Bool { values[key] = value; return true }
}
@MainActor enum WebhookTransportFixture {
  struct Request { var payload: Data; var continuation: CheckedContinuation<WebhookResult, Never>? }
  static var requests: [Request] = []
  static func reset() { precondition(requests.allSatisfy { $0.continuation == nil }); requests = [] }
  static func send(_ data: Data, to url: URL, authorize: @escaping @MainActor @Sendable () -> Bool) async -> WebhookResult {
    precondition(authorize())
    return await withCheckedContinuation { requests.append(.init(payload: data, continuation: $0)) }
  }
  static func entered(_ count: Int) async {
    for _ in 0..<10000 { if requests.count >= count { return }; await Task.yield() }
    preconditionFailure("Webhook fixture did not start")
  }
  static func finish(_ index: Int, success: Bool) {
    let waiting = requests[index].continuation; requests[index].continuation = nil
    waiting?.resume(returning: .init(date: .now, succeeded: success, message: "fixture"))
  }
}
final class WebhookURLProtocol: URLProtocol, @unchecked Sendable {
  struct Options { var count = 0; var status = 200; var declaredLength: Int?; var bodySize = 0; var hold = false }
  static let options = Mutex(Options())
  static var count: Int { options.withLock { $0.count } }
  static func configure(status: Int = 200, declaredLength: Int? = nil, bodySize: Int = 0, hold: Bool = false) {
    options.withLock { $0 = .init(status: status, declaredLength: declaredLength, bodySize: bodySize, hold: hold) }
  }
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let value = Self.options.withLock { $0.count += 1; return $0 }
    var headers: [String: String] = [:]
    if let length = value.declaredLength { headers["Content-Length"] = String(length) }
    if value.status == 302 { headers["Location"] = "https://example.invalid/redirected" }
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: value.status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
    if value.bodySize > 0 { client?.urlProtocol(self, didLoad: Data(repeating: 1, count: value.bodySize)) }
    if !value.hold { client?.urlProtocolDidFinishLoading(self) }
  }
  override func stopLoading() {}
}
enum MediaFiles {
  static func reference(for url: URL) -> String? { url.lastPathComponent }
  static func resolve(_ name: String) -> URL? { nil }
  static func writePhoto(_ data: Data) -> String? { nil }
  @discardableResult static func deletePhoto(_ name: String) -> Bool { false }
}
struct TemplateSummary: Hashable, Codable {}
enum SummaryPreviewCache { static func preview(for id: UUID, summary: String, build: (String) -> String) -> String { build(summary) } }
enum MarkdownBlockParser { static func hasBlockStructure(_ text: String) -> Bool { false }; static func overview(of text: String) -> String { text } }
