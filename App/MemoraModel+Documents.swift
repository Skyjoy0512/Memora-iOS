import Foundation

// Documents: written documents and slides made from the records.
extension MemoraModel {
  func document(id: UUID) -> MemoraDocument? {
    documents.first { $0.id == id }
  }

  /// Stores a new document and waits for the write, so the agent only reports
  /// a document as made once it is really saved.
  @discardableResult
  func addDocument(_ document: MemoraDocument) -> Bool {
    guard isStoreWritable() else { return false }
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
  func updateDocument(_ id: UUID, title: String, body: String) {
    guard isStoreWritable(), let index = documents.firstIndex(where: { $0.id == id }) else { return }
    documents[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    switch documents[index].kind {
    case .document:
      documents[index].markdown = body
    case .slides:
      documents[index].slides = DocumentSlide.slides(fromOutline: body)
    }
    documents[index].updatedAt = .now
    persistDocuments()
  }

  func deleteDocument(_ id: UUID) {
    guard isStoreWritable() else { return }
    documents.removeAll { $0.id == id }
    persistDocuments()
  }
}
