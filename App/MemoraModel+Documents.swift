import Foundation

// Documents: written documents and slides made from the records.
extension MemoraModel {
  /// Imported sources can share a restored file with an Office artifact.
  var retainedOfficeFileReferences: Set<String> {
    Set(documents.flatMap(\.artifactFileReferences) + companyTemplates.map(\.fileReference))
  }

  func document(from message: AIChatMessage, exportedAnswer: String? = nil) -> MemoraDocument {
    let question: String?
    if message.residentName == nil, let index = aiMessages.firstIndex(where: { $0.id == message.id }) {
      question = aiMessages[..<index].last { $0.role == .user }?.text
    } else {
      question = nil
    }
    return AIAnswerDocumentBuilder.make(message: message, question: question, provenance: artifactProvenance(for: message),
      exportedAnswer: exportedAnswer)
  }

  func document(id: UUID) -> MemoraDocument? {
    documents.first { $0.id == id }
  }

  /// Stores a new document and waits for the write, so the agent only reports
  /// a document as made once it is really saved.
  @discardableResult
  func addDocument(_ document: MemoraDocument) -> Bool {
    guard !isRestoring, isStoreWritable(), document.hasValidRevisions,
          document.presentationPlan?.isValid(for: document.slides) ?? true, document.provenance?.isValid ?? true,
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

  @discardableResult
  func deleteDocument(_ id: UUID) -> Bool {
    guard !isRestoring, isStoreWritable() else { return false }
    guard let document = document(id: id) else { return false }
    let candidate = documents.filter { $0.id != id }
    guard persistNow(candidate, forKey: StorageKey.documents) else { return false }
    documents = candidate
    invalidateProjectEvidence([.document(id)])
    let workspace = currentTeamID, generation = aiWorkspaceGeneration
    Task {
      guard workspace == currentTeamID, generation == aiWorkspaceGeneration else { return }
      let retained = Set(documents.flatMap(\.artifactFileReferences) + companyTemplates.map(\.fileReference) + projectSources.flatMap(\.fileReferences))
      await ProjectSourceFiles.shared.remove(document.artifactFileReferences.filter { !retained.contains($0) })
    }
    return true
  }

  @discardableResult
  func updateDocumentSlides(_ id: UUID, title: String, slides: [DocumentSlide], expectedUpdatedAt: Date,
                            plan: PresentationPlan? = nil) -> Bool {
    guard !isRestoring, isStoreWritable(), let index = documents.firstIndex(where: { $0.id == id }),
          documents[index].updatedAt == expectedUpdatedAt, documents[index].kind == .slides,
          documents[index].hasValidRevisions, (documents[index].contentRevision ?? 0) < Int.max,
          !slides.isEmpty, slides.count <= 65, Set(slides.map(\.id)).count == slides.count else { return false }
    var edited = documents[index]
    edited.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    edited.slides = slides
    edited.presentationPlan = (plan ?? edited.presentationPlan)?.reconciled(with: slides)
    guard edited.presentationPlan?.isValid(for: slides) ?? true else { return false }
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
