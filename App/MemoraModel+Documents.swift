import Foundation

// Documents: written documents and slides made from the records.
extension MemoraModel {
  func document(from message: AIChatMessage) -> MemoraDocument {
    let question: String?
    if message.residentName == nil, let index = aiMessages.firstIndex(where: { $0.id == message.id }) {
      question = aiMessages[..<index].last { $0.role == .user }?.text
    } else {
      question = nil
    }
    return AIAnswerDocumentBuilder.make(message: message, question: question, provenance: artifactProvenance(for: message))
  }

  func document(id: UUID) -> MemoraDocument? {
    documents.first { $0.id == id }
  }

  /// Stores a new document and waits for the write, so the agent only reports
  /// a document as made once it is really saved.
  @discardableResult
  func addDocument(_ document: MemoraDocument) -> Bool {
    guard !isRestoring, isStoreWritable(), document.provenance?.isValid ?? true,
          document.provenance.map({ $0.workspaceID == currentTeamID }) ?? true else { return false }
    var candidate = documents
    candidate.insert(document, at: 0)
    let stored = persistBatch {
      [(key: StorageKey.documents, data: try RecordStore.encoded(candidate))]
    }
    guard stored else { return false }
    documents = candidate
    return true
  }

  /// Replaces a document's title and body. The body is markdown for a written
  /// document and the slide outline for slides.
  @discardableResult
  func updateDocument(_ id: UUID, title: String, body: String) -> Bool {
    guard isStoreWritable(), let index = documents.firstIndex(where: { $0.id == id }) else { return false }
    let oldArtifact = documents[index].artifactFileReference
    var candidate = documents
    candidate[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    switch candidate[index].kind {
    case .document:
      candidate[index].markdown = body
    case .slides:
      candidate[index].slides = DocumentSlide.slides(fromOutline: body)
    }
    candidate[index].artifactFileReference = nil
    candidate[index].artifactFormat = nil
    candidate[index].companyTemplateID = nil
    candidate[index].updatedAt = .now
    guard persistBatch({ [(key: StorageKey.documents, data: try RecordStore.encoded(candidate))] }) else { return false }
    documents = candidate
    if let oldArtifact { Task { await ProjectSourceFiles.shared.remove([oldArtifact]) } }
    return true
  }

  func deleteDocument(_ id: UUID) {
    guard isStoreWritable() else { return }
    guard let document = document(id: id) else { return }
    let candidate = documents.filter { $0.id != id }
    guard persistNow(candidate, forKey: StorageKey.documents) else { return }
    documents = candidate
    invalidateProjectEvidence([.document(id)])
    if let name = document.artifactFileReference { Task { await ProjectSourceFiles.shared.remove([name]) } }
  }
}
