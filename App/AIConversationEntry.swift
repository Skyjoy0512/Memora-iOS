import Foundation

/// One saved question and answer. The engine and model are kept so reopening a
/// history entry shows what really produced it, not what is set today.
struct AIConversationEntry: Identifiable, Hashable, Codable {
  var id: UUID
  var question: String
  var answer: String
  var sourceMessageID: UUID?
  var generatedUI: JSONRenderSnapshot?
  var scopeLabel: String
  var engineLabel: String?
  var modelLabel: String?
  var createdAt: Date
  var cloudProvenance: AIConversationProvenance?
  var webResearchReportID: UUID?
  var episode: AIEpisode?
  var sourceCitations: [ProjectCitation]?
  var attachmentCitations: [AIAttachmentCitation]?
  var attachment: AIAttachmentFileReference?

  init(
    id: UUID,
    question: String,
    answer: String,
    scopeLabel: String,
    engineLabel: String? = nil,
    modelLabel: String? = nil,
    createdAt: Date,
    cloudProvenance: AIConversationProvenance? = nil,
    webResearchReportID: UUID? = nil,
    episode: AIEpisode? = nil,
    sourceCitations: [ProjectCitation]? = nil,
    attachmentCitations: [AIAttachmentCitation]? = nil,
    attachment: AIAttachmentFileReference? = nil,
    sourceMessageID: UUID? = nil,
    generatedUI: JSONRenderSnapshot? = nil
  ) {
    self.id = id
    self.question = question
    self.answer = answer
    self.sourceMessageID = sourceMessageID
    self.generatedUI = generatedUI
    self.scopeLabel = scopeLabel
    self.engineLabel = engineLabel
    self.modelLabel = modelLabel
    self.createdAt = createdAt
    self.cloudProvenance = cloudProvenance
    self.webResearchReportID = webResearchReportID
    self.episode = episode
    self.sourceCitations = sourceCitations
    self.attachmentCitations = attachmentCitations
    self.attachment = attachment
  }

  /// Lenient so entries saved before the engine was recorded still decode.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    question = try container.decode(String.self, forKey: .question)
    let decodedAnswer = try container.decode(String.self, forKey: .answer)
    answer = decodedAnswer
    sourceMessageID = try? container.decode(UUID.self, forKey: .sourceMessageID)
    let ui = try? container.decode(JSONRenderSnapshot.self, forKey: .generatedUI)
    generatedUI = ui.flatMap { $0.isValid && $0.fingerprint == JSONRenderSnapshot.fingerprint(decodedAnswer) ? $0 : nil }
    scopeLabel = try container.decode(String.self, forKey: .scopeLabel)
    engineLabel = try container.decodeIfPresent(String.self, forKey: .engineLabel)
    modelLabel = try container.decodeIfPresent(String.self, forKey: .modelLabel)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    cloudProvenance = try? container.decode(AIConversationProvenance.self, forKey: .cloudProvenance)
    webResearchReportID = try container.decodeIfPresent(UUID.self, forKey: .webResearchReportID)
    episode = try container.decodeIfPresent(AIEpisode.self, forKey: .episode)
    let citations = try container.decodeIfPresent([ProjectCitation].self, forKey: .sourceCitations)
    sourceCitations = (citations?.count ?? 0) <= 64 ? citations : nil
    let clips = try? container.decode([AIAttachmentCitation].self, forKey: .attachmentCitations)
    attachmentCitations = (clips?.count ?? 0) <= 64 && (clips?.allSatisfy(\.isValid) ?? true) &&
      Set((clips ?? []).map(\.number)).count == (clips?.count ?? 0) ? clips : nil
    let file = try container.decodeIfPresent(AIAttachmentFileReference.self, forKey: .attachment)
    attachment = file?.isValid == true ? file : nil
  }
}
