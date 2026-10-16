import Foundation

/// Saved locally. Opening Mail is not evidence that a message was sent or delivered.
struct MailDraft: Identifiable, Hashable, Codable, Sendable {
  var id = UUID()
  var recipients: [String]
  var subject: String
  var body: String
  var cc: [String] = []
  var bcc: [String] = []
  var createdAt = Date.now
  var updatedAt = Date.now
  var personIDs: [UUID] = []
  var projectID: UUID?
  var recordIDs: [UUID] = []
  var sourceMessageID: UUID?
  var workspaceID: String?
  var provenance: ArtifactProvenance?
  var status: Status = .draft
  enum Status: String, Codable, Sendable { case draft, archived }

  var plainText: String {
    var lines: [String] = []
    if !recipients.isEmpty { lines.append("宛先: " + recipients.joined(separator: ", ")) }
    if !cc.isEmpty { lines.append("CC: " + cc.joined(separator: ", ")) }
    if !bcc.isEmpty { lines.append("BCC: " + bcc.joined(separator: ", ")) }
    lines.append("件名: " + subject)
    return lines.joined(separator: "\n") + "\n\n" + body
  }

  static func validAddress(_ value: String) -> Bool {
    value.count <= 254 && value.range(of: #"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,63}$"#, options: .regularExpression) != nil
  }
}
