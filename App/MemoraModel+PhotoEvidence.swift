import Foundation

extension MemoraModel {
  func photoEvidenceEntries(for names: Set<String>) async -> [MediaIndexEntry] {
    let generation = aiWorkspaceGeneration
    guard !names.isEmpty, reconcileMediaIndex() else { return [] }
    await readPendingMediaText(for: names, limit: 6)
    guard !Task.isCancelled, aiWorkspaceGeneration == generation,
          currentTeamID == nil, !isRestoring, !isStoreProtected else { return [] }
    return mediaIndexEntries.filter { names.contains($0.name) && $0.textReadAt != nil && !$0.text.isEmpty }
  }

  func currentPhotoEvidence(_ citation: ProjectCitation) -> MediaIndexEntry? {
    guard let photo = citation.photo, !citation.excerpt.isEmpty, case .meeting(let id) = citation.target,
          let record = meeting(id: id), citation.recordedAt == record.createdAt,
          let entry = mediaIndexEntries.first(where: { $0.name == photo.name && $0.recordID == id }),
          entry.byteCount == photo.byteCount, entry.fileModifiedAt == photo.modifiedAt,
          entry.textReadAt == photo.textReadAt, entry.text.contains(citation.excerpt),
          mediaIndexEntryHasLiveOriginal(entry) else { return nil }
    return entry
  }

  nonisolated static func photoEvidenceChunks(_ entries: [MediaIndexEntry], namespace: UUID,
                                             allowed: Set<ProjectCitation.Target>) -> [ProjectEvidenceChunk] {
    entries.flatMap { entry -> [ProjectEvidenceChunk] in
      let target = ProjectCitation.Target.meeting(entry.recordID)
      guard allowed.contains(target), let modifiedAt = entry.fileModifiedAt,
            let textReadAt = entry.textReadAt else { return [] }
      let photo = ProjectCitation.Photo(name: entry.name, byteCount: entry.byteCount,
        modifiedAt: modifiedAt, textReadAt: textReadAt)
      return ProjectContextBuilder.split(entry.text, projectID: namespace, target: target,
        title: entry.recordTitle, recordedAt: entry.recordDate, photo: photo)
    }
  }

  func recordPhotoContext(_ record: Meeting, question: String, budget: Int) async -> ProjectContextBuilder.Context {
    let entries = await photoEvidenceEntries(for: Set(record.photoFileNames ?? []))
    let id = record.id
    return await Task.detached(priority: .userInitiated) {
      let allowed: Set<ProjectCitation.Target> = [.meeting(id)]
      let chunks = Self.photoEvidenceChunks(entries, namespace: id, allowed: allowed)
      return ProjectContextBuilder.build(question: question, projectID: id, chunks: chunks,
        allowed: allowed, characterBudget: budget, marker: .photo)
    }.value
  }
}
