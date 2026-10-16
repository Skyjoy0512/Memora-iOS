import Foundation

/// A local resume document, separate from exchange history and execution grants.
struct AIConversationSnapshot: Codable, Sendable {
  static let maximumBytes = 8 * 1_024 * 1_024
  var version = 1
  var workspaceID: String?
  var personID: UUID?
  var conversationID: UUID?
  var turns: [Turn]

  init(messages: [AIChatMessage], workspaceID: String?, personID: UUID? = nil, conversationID: UUID? = nil) {
    self.personID = personID
    self.conversationID = conversationID
    self.workspaceID = workspaceID
    // An unfinished resident post has never been delivered. It is not a result.
    turns = messages.filter { $0.residentName == nil || !$0.isThinking }.map(Turn.init)
  }

  static func decode(_ data: Data, workspaceID: String?) throws -> Self {
    guard data.count <= maximumBytes else { throw Failure.invalid }
    let snapshot = try JSONDecoder().decode(Self.self, from: data)
    guard snapshot.isValid, snapshot.workspaceID == workspaceID else { throw Failure.invalid }
    return snapshot
  }

  var isValid: Bool {
    version == 1 && turns.count <= 2_000 && Set(turns.map(\.id)).count == turns.count
      && turns.reduce(128, { $0 + $1.maximumEncodedBytes }) <= Self.maximumBytes
      && (workspaceID?.utf8.count ?? 0) <= 256
      && turns.allSatisfy { turn in
        ["user", "assistant"].contains(turn.role) && turn.sources.count <= 256
          && turn.pluginIDs.count <= 32 && turn.suggestions.count <= 30
          && turn.documentIDs.count <= 256 && turn.webResearchReportIDs.count <= 256
          && (turn.createdTaskIDs?.count ?? 0) <= 30
          && turn.sources.allSatisfy { $0.excerpts.count <= 20 }
          && (turn.cloudProvenance?.references.count ?? 0) <= 256
          && (turn.artifactProvenance?.isValid ?? true)
          && (turn.artifactProvenance.map { $0.workspaceID == workspaceID } ?? true)
          && turn.createdAt.timeIntervalSince1970.isFinite
          && (turn.finishedAt?.timeIntervalSince1970.isFinite ?? true)
          && (turn.attachment?.isValid ?? true) && (turn.mentions?.count ?? 0) <= 32
      }
  }

  func restoredMessages() -> [AIChatMessage] { turns.map { $0.restoredMessage() } }

  enum Failure: Error { case invalid }

  struct Turn: Codable, Sendable {
    var id: UUID
    var role: String
    var text: String
    var attachment: AIAttachmentFileReference?
    var mentions: [ComposerMention]?
    var createdAt: Date
    var finishedAt: Date?
    var wasInterrupted: Bool
    var didChangeData: Bool
    var pluginIDs: [String]
    var details: AIAnswerDetails?
    var sources: [AIChatSource]
    var documentIDs: [UUID]
    var createdTaskIDs: [UUID]?
    var webResearchReportIDs: [UUID]
    var cloudProvenance: AIConversationProvenance?
    var artifactProvenance: ArtifactProvenance?
    var residentName: String?
    var residentAgentID: UUID?
    var residentSymbol: MemoraIcon?
    var suggestions: [String]

    /// JSON can escape a UTF-8 byte into six bytes. Count conservatively before
    /// handing the immutable value to the existing serial background writer.
    var maximumEncodedBytes: Int {
      let metadata = [residentName, attachment?.name, attachment?.fileName, details?.scopeLabel, details?.engineLabel, details?.modelLabel,
        cloudProvenance?.workspaceID, cloudProvenance?.memoryFingerprint, artifactProvenance?.workspaceID].compactMap { $0 }
      let sourceStrings = sources.flatMap { [$0.title] + $0.excerpts.map(\.text) }
      let fingerprints = (cloudProvenance?.references.map(\.fingerprint) ?? [])
        + (artifactProvenance?.records.map(\.fingerprint) ?? []) + (artifactProvenance?.projectSources.map(\.fingerprint) ?? [])
      let mentionStrings = mentions?.flatMap { [$0.label, $0.pluginID] } ?? []
      let bytes = ([text] + pluginIDs + suggestions + metadata + sourceStrings + fingerprints + mentionStrings)
        .reduce(0) { $0 + $1.utf8.count }
      return 2_048 + bytes * 6 + (sources.count + sources.reduce(0) { $0 + $1.excerpts.count }
        + documentIDs.count + (createdTaskIDs?.count ?? 0) + webResearchReportIDs.count + fingerprints.count + (mentions?.count ?? 0)) * 256
    }

    init(_ message: AIChatMessage) {
      id = message.id
      role = message.role == .user ? "user" : "assistant"
      text = message.text
      attachment = message.attachment.flatMap(AIAttachmentFileReference.init)
      mentions = message.mentions
      createdAt = message.createdAt
      finishedAt = message.finishedAt
      wasInterrupted = message.isThinking
      didChangeData = message.didChangeData
      pluginIDs = message.pluginIDs
      details = message.details
      sources = message.sources
      documentIDs = message.documentIDs
      createdTaskIDs = message.createdTaskIDs
      webResearchReportIDs = message.webResearchReportIDs
      cloudProvenance = message.cloudProvenance
      artifactProvenance = message.artifactProvenance
      residentName = message.residentName
      residentAgentID = message.residentAgentID
      residentSymbol = message.residentSymbol
      suggestions = message.suggestions
    }

    func restoredMessage() -> AIChatMessage {
      var message = AIChatMessage(role: role == "user" ? .user : .assistant, text: text)
      message.attachment = attachment?.resolve()
      message.mentions = (mentions ?? []).filter { $0.isValid(in: text) && pluginIDs.contains($0.pluginID) }
      message.id = id
      message.createdAt = createdAt
      message.finishedAt = finishedAt
      message.pluginIDs = pluginIDs
      message.details = details
      message.sources = sources
      message.documentIDs = documentIDs
      message.createdTaskIDs = createdTaskIDs ?? []
      message.webResearchReportIDs = webResearchReportIDs
      message.cloudProvenance = cloudProvenance
      message.artifactProvenance = artifactProvenance
      message.residentName = residentName
      message.residentAgentID = residentAgentID
      message.residentSymbol = residentSymbol
      message.suggestions = suggestions
      // Nothing here restores tool policies, UI mutation IDs, continuations or tasks.
      message.didChangeData = didChangeData || wasInterrupted
      if wasInterrupted {
        message.text = NativeAIInterface.response(text).markdown
          + (text.isEmpty ? "" : "\n\n")
          + "前回の処理は中断されました。操作は自動再実行しません。変更先の状態を確認してから、新しい依頼を送ってください。"
        message.cloudProvenance = nil
        message.finishedAt = .now
      }
      return message
    }
  }
}
