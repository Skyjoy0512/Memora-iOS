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
    guard !isRestoring, isStoreWritable(), document.hasValidRevisions, document.provenance?.isValid ?? true,
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
  func updateDocument(_ id: UUID, title: String, body: String, expectedUpdatedAt: Date? = nil) -> Bool {
    guard !isRestoring, isStoreWritable(), let index = documents.firstIndex(where: { $0.id == id }),
          expectedUpdatedAt.map({ $0 == documents[index].updatedAt }) ?? true,
          let edited = documents[index].editing(title: title, body: body) else { return false }
    guard edited != documents[index] else { return true }
    var candidate = documents
    candidate[index] = edited
    guard persistBatch({ [(key: StorageKey.documents, data: try RecordStore.encoded(candidate))] }) else { return false }
    documents = candidate
    return true
  }

  func deleteDocument(_ id: UUID) {
    guard isStoreWritable() else { return }
    guard let document = document(id: id) else { return }
    let candidate = documents.filter { $0.id != id }
    guard persistNow(candidate, forKey: StorageKey.documents) else { return }
    documents = candidate
    invalidateProjectEvidence([.document(id)])
    if let name = document.artifactFileReference,
       !candidate.contains(where: { $0.artifactFileReference == name }),
       !companyTemplates.contains(where: { $0.fileReference == name }) {
      Task { await ProjectSourceFiles.shared.remove([name]) }
    }
  }

  @discardableResult
  func updateDocumentSlides(_ id: UUID, title: String, slides: [DocumentSlide], expectedUpdatedAt: Date) -> Bool {
    guard !isRestoring, isStoreWritable(), let index = documents.firstIndex(where: { $0.id == id }),
          documents[index].updatedAt == expectedUpdatedAt, documents[index].kind == .slides,
          documents[index].hasValidRevisions, (documents[index].contentRevision ?? 0) < Int.max,
          !slides.isEmpty, Set(slides.map(\.id)).count == slides.count else { return false }
    var edited = documents[index]
    edited.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    edited.slides = slides
    guard edited != documents[index] else { return true }
    edited.contentRevision = (edited.contentRevision ?? 0) + 1
    edited.updatedAt = .now
    var candidate = documents; candidate[index] = edited
    guard persistBatch({ [(key: StorageKey.documents, data: try RecordStore.encoded(candidate))] }) else { return false }
    documents = candidate
    invalidateProjectEvidence([.document(id)])
    return true
  }
}
