import Foundation

struct WebhookDeliveryJob {
  var endpoint: WebhookEndpoint
  var address: String
  var workspaceID: String?
  var generation: UUID
  var meeting: Meeting
  var tasks: [MemoraTask]
  var isTest: Bool
  var task: Task<Void, Never>?
}
