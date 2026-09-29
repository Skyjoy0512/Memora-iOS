import Foundation

/// An email the agent wrote for the person to review and send themselves.
struct MailDraft: Identifiable, Hashable {
  var id = UUID()
  var recipients: [String]
  var subject: String
  var body: String

  /// The draft as plain text, for sharing when Mail is not set up.
  var plainText: String {
    var text = "件名: \(subject)\n\n\(body)"
    if !recipients.isEmpty {
      text = "宛先: \(recipients.joined(separator: ", "))\n" + text
    }
    return text
  }
}
