import Foundation

struct PreparedAIAttachment: Sendable {
  var id: UUID
  var name: String
  var url: URL
  var text: String?
  var failure: String?
  var notice: String?

  func matches(_ attachment: AIAttachment) -> Bool {
    id == attachment.id && name == attachment.name && url == attachment.url
  }
}
