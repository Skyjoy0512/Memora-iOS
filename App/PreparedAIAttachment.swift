import Foundation

struct PreparedAIAttachment: Sendable {
  var id: UUID
  var name: String
  var url: URL
  var text: String?
  var failure: String?
  var notice: String?
  var preparedQuestion: String?
  var additionalFileIDs: [UUID]?

  func matches(_ attachment: AIAttachment) -> Bool {
    id == attachment.id && name == attachment.name && url == attachment.url &&
      (additionalFileIDs ?? []) == (attachment.additionalFiles ?? []).map(\.id)
  }
}
