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

  func indexedPhotoContext(for recordIDs: Set<UUID>, question: String, budget: Int) async -> ProjectContextBuilder.Context {
    let empty = ProjectContextBuilder.Context(text: "", used: [], matchedCount: 0)
    guard !Task.isCancelled, currentTeamID == nil, !isRestoring, !isStoreProtected, budget > 0 else { return empty }
    let generation = aiWorkspaceGeneration
    let entries = mediaIndexEntries.filter { recordIDs.contains($0.recordID) && $0.textReadAt != nil && !$0.text.isEmpty }
    guard !entries.isEmpty else { return empty }
    let candidates = await Task.detached(priority: .userInitiated) {
      let terms = ProjectContextBuilder.queryGrams(question).sorted().prefix(24)
      let ranked = entries.enumerated().compactMap { index, entry -> (Int, Int, MediaIndexEntry)? in
        let matches = terms.count { entry.text.range(of: $0, options: [.caseInsensitive, .widthInsensitive]) != nil }
        return matches > 0 ? (index, matches, entry) : nil
      }.sorted { left, right in
        left.1 == right.1 ? left.0 < right.0 : left.1 > right.1
      }
      return ranked.prefix(24).map { $0.2 }
    }.value
    guard !Task.isCancelled, aiWorkspaceGeneration == generation else { return empty }
    let selected = candidates.filter { mediaIndexEntryHasLiveOriginal($0) }
    guard !selected.isEmpty else { return empty }
    return await Task.detached(priority: .userInitiated) {
      let allowed = Set(selected.map { ProjectCitation.Target.meeting($0.recordID) })
      let namespace = UUID()
      let chunks = Self.photoEvidenceChunks(selected, namespace: namespace, allowed: allowed)
      return ProjectContextBuilder.build(question: question, projectID: namespace, chunks: chunks,
        allowed: allowed, characterBudget: budget, marker: .photo)
    }.value
  }
}
