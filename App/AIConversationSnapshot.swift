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
          && (turn.attachmentCitations?.count ?? 0) <= 64
          && (turn.attachmentCitations ?? []).allSatisfy(\.isValid)
          && Set((turn.attachmentCitations ?? []).map(\.number)).count == (turn.attachmentCitations?.count ?? 0)
          && (turn.sourceCitations?.count ?? 0) <= 64
          && (turn.sourceCitations ?? []).allSatisfy { $0.excerpt.utf8.count <= 8_000 && ($0.page.map { $0 > 0 } ?? true) && ($0.time.map { $0.isFinite && $0 >= 0 } ?? true) }
          && (turn.cloudProvenance?.references.count ?? 0) <= 256
          && (turn.artifactProvenance?.isValid ?? true)
          && (turn.artifactProvenance.map { $0.workspaceID == workspaceID } ?? true)
          && (turn.generatedUI?.isValid ?? true)
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
    var generatedUI: JSONRenderSnapshot?
    var attachment: AIAttachmentFileReference?
    var mentions: [ComposerMention]?
    var createdAt: Date
    var finishedAt: Date?
    var wasInterrupted: Bool
    var didChangeData: Bool
    var hasUnconfirmedDataChange: Bool?
    var pluginIDs: [String]
    var details: AIAnswerDetails?
    var sources: [AIChatSource]
    var sourceCitations: [ProjectCitation]?
    var attachmentCitations: [AIAttachmentCitation]?
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
      let attachmentStrings = attachment.map { ([$0] + ($0.additionalFiles ?? [])).flatMap { [$0.name, $0.fileName, $0.originalURL?.absoluteString ?? ""] } } ?? []
      let metadata = [residentName, details?.scopeLabel, details?.engineLabel, details?.modelLabel,
        cloudProvenance?.workspaceID, cloudProvenance?.memoryFingerprint, artifactProvenance?.workspaceID].compactMap { $0 }
      let sourceStrings = sources.flatMap { [$0.title] + $0.excerpts.map(\.text) }
        + (sourceCitations ?? []).flatMap { [$0.title, $0.excerpt] }
      let attachmentEvidence = (attachmentCitations ?? []).flatMap { [$0.file.name, $0.file.fileName, $0.file.originalURL?.absoluteString ?? "", $0.excerpt] }
      let fingerprints = (cloudProvenance?.references.map(\.fingerprint) ?? [])
        + (artifactProvenance?.records.map(\.fingerprint) ?? []) + (artifactProvenance?.projectSources.map(\.fingerprint) ?? [])
      let mentionStrings = mentions?.flatMap { [$0.label, $0.pluginID] } ?? []
      let bytes = ([text] + pluginIDs + suggestions + metadata + attachmentStrings + sourceStrings + attachmentEvidence + fingerprints + mentionStrings)
        .reduce(0) { $0 + $1.utf8.count }
      return 2_048 + (generatedUI?.maximumEncodedBytes ?? 0) + bytes * 6 + (sources.count + sources.reduce(0) { $0 + $1.excerpts.count }
        + documentIDs.count + (createdTaskIDs?.count ?? 0) + webResearchReportIDs.count + fingerprints.count + (mentions?.count ?? 0)
        + (sourceCitations?.count ?? 0) + (attachmentCitations?.count ?? 0) + (attachment?.additionalFiles?.count ?? 0)) * 256
    }

    init(_ message: AIChatMessage) {
      id = message.id
      role = message.role == .user ? "user" : "assistant"
      text = message.text
      generatedUI = message.generatedUI
      attachment = message.attachment.flatMap(AIAttachmentFileReference.init)
      mentions = message.mentions
      createdAt = message.createdAt
      finishedAt = message.finishedAt
      wasInterrupted = message.isThinking
      didChangeData = message.didChangeData
      hasUnconfirmedDataChange = message.hasUnconfirmedDataChange
      pluginIDs = message.pluginIDs
      details = message.details
      sources = message.sources
      sourceCitations = message.sourceCitations
      attachmentCitations = message.attachmentCitations
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
      message.generatedUI = generatedUI.flatMap { $0.isValid && $0.fingerprint == JSONRenderSnapshot.fingerprint(text) && !wasInterrupted ? $0 : nil }
      message.attachment = attachment?.resolve()
      message.mentions = (mentions ?? []).filter { $0.isValid(in: text) && pluginIDs.contains($0.pluginID) }
      message.id = id
      message.createdAt = createdAt
      message.finishedAt = finishedAt
      message.pluginIDs = pluginIDs
      message.details = details
      message.sources = sources
      message.sourceCitations = sourceCitations ?? []
      message.attachmentCitations = attachmentCitations ?? []
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
      message.didChangeData = didChangeData
      message.hasUnconfirmedDataChange = (hasUnconfirmedDataChange ?? false) || wasInterrupted
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
