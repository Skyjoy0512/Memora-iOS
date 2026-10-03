import Foundation

/// How the last send to an endpoint went, shown beside it in settings.
struct WebhookResult: Hashable {
  var date: Date
  var succeeded: Bool
  var message: String
}
