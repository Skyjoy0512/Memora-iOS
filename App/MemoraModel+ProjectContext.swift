import Foundation

extension MemoraModel {
  func invalidateProjectEvidence(_ targets: [ProjectCitation.Target]) {
    Task { try? await ProjectSearchIndex.shared.remove(targets: targets) }
  }

  func projectEvidenceAllowed(_ target: ProjectCitation.Target, projectID: UUID, cloud: Bool) -> Bool {
    guard currentTeamID == nil, !isRestoring, !isStoreProtected, space(id: projectID) != nil else { return false }
    switch target {
    case .source(let id):
      guard let value = source(id: id), value.projectID == projectID, value.canProvideText else { return false }
      return !cloud || RecordAccessPolicy.allows(value.privacy, purpose: .cloudAI)
    case .meeting(let id):
      guard let value = meeting(id: id), value.spaceID == projectID else { return false }
      return !cloud || allowsRecordAccess(id, purpose: .cloudAI)
    case .document(let id):
      // Existing documents have no external-send permission. They remain local
      // evidence until a document-specific permission is explicitly provided.
      return !cloud && document(id: id)?.spaceID == projectID
    case .task(let id):
      guard let task = self.task(id: id),
            let recordID = task.meetingID, meeting(id: recordID)?.spaceID == projectID else { return false }
      return !cloud || allowsTaskAccess(task, purpose: .cloudAI)
    }
  }

  func projectEvidenceStillAvailable(_ citations: [ProjectCitation], projectID: UUID, cloud: Bool) async -> Bool {
    let workspaceID = currentTeamID
    guard citations.count <= 128 else { return false }
    for citation in citations {
      guard !Task.isCancelled, currentTeamID == workspaceID,
            projectCitationAllowed(citation, projectID: projectID, cloud: cloud) else { return false }
      let text: String
      switch citation.target {
      case .source(let id):
        guard let name = source(id: id)?.extractedTextReference,
              let blocks = try? await ProjectSourceTextReader.readAsync(name),
              source(id: id)?.extractedTextReference == name else { return false }
        text = blocks.filter { citation.page == nil || $0.page == citation.page }.map(\.text).joined(separator: "\n")
      case .meeting(let id):
        guard let record = meeting(id: id) else { return false }
        if let photo = citation.photo {
          guard let entry = projectPhotoEvidence(photo, recordID: id) else { return false }
          text = entry.text
        } else {
          text = ([record.summary, record.summaryKnowledgeText] + record.transcript.map(\.text)).joined(separator: "\n")
        }
      case .document(let id): text = document(id: id)?.plainText ?? ""
      case .task(let id):
        guard let task = self.task(id: id) else { return false }
        text = [task.title, task.detail, task.assignee].compactMap { $0 }.joined(separator: "\n")
      }
      guard !Task.isCancelled, currentTeamID == workspaceID, !citation.excerpt.isEmpty, text.contains(citation.excerpt),
            projectCitationAllowed(citation, projectID: projectID, cloud: cloud) else { return false }
    }
    return !Task.isCancelled && currentTeamID == workspaceID && !isRestoring && !isStoreProtected
  }

  func projectCitationAllowed(_ citation: ProjectCitation, projectID: UUID, cloud: Bool) -> Bool {
    guard projectEvidenceAllowed(citation.target, projectID: projectID, cloud: cloud) else { return false }
    if let photo = citation.photo {
      guard !cloud, case .meeting(let id) = citation.target,
            projectPhotoEvidence(photo, recordID: id) != nil else { return false }
    }
    if case .meeting(let id) = citation.target, let recordedAt = citation.recordedAt {
      return meeting(id: id)?.createdAt == recordedAt
    }
    return true
  }

  private func projectPhotoEvidence(_ photo: ProjectCitation.Photo, recordID: UUID) -> MediaIndexEntry? {
    guard let entry = mediaIndexEntries.first(where: { $0.name == photo.name && $0.recordID == recordID }),
          entry.byteCount == photo.byteCount, entry.fileModifiedAt == photo.modifiedAt,
          entry.textReadAt == photo.textReadAt,
          mediaIndexEntryHasLiveOriginal(entry) else { return nil }
    return entry
  }

  func projectContext(question: String, projectID: UUID, cloud: Bool, budget: Int,
                      onlyTarget: ProjectCitation.Target? = nil,
                      selectedTargets: Set<ProjectCitation.Target>? = nil) async -> ProjectContextBuilder.Context {
    let workspaceID = currentTeamID
    let generation = aiWorkspaceGeneration
    let empty = ProjectContextBuilder.build(question: question, projectID: projectID, chunks: [], allowed: [], characterBudget: 0)
    guard !Task.isCancelled, !isRestoring, !isStoreProtected, space(id: projectID) != nil else { return empty }
    var inputs: [ProjectEvidenceInput] = []
    var allowed: Set<ProjectCitation.Target> = []
    let records = meetings.filter { $0.spaceID == projectID }
    for record in records where (onlyTarget == nil || onlyTarget == .meeting(record.id))
      && (selectedTargets?.contains(.meeting(record.id)) ?? true)
      && projectEvidenceAllowed(.meeting(record.id), projectID: projectID, cloud: cloud) {
      let target = ProjectCitation.Target.meeting(record.id)
      allowed.insert(target)
      var blocks = [ProjectSourceText(text: record.summary)]
      if !record.summaryKnowledgeText.isEmpty {
        blocks += record.summaryKnowledgeText.components(separatedBy: "\n").filter { !record.summary.contains($0) }.map { ProjectSourceText(text: $0) }
      }
      blocks += record.transcript.map { ProjectSourceText(text: $0.text, time: $0.timestamp) }
      inputs.append(ProjectEvidenceInput(target: target, title: record.displayTitle, blocks: blocks, recordedAt: record.createdAt))
    }
    let recordIDs = Set(records.map(\.id))
    for task in tasks where task.meetingID.map(recordIDs.contains) == true && !task.isCompleted {
      let target = ProjectCitation.Target.task(task.id)
      guard onlyTarget == nil || onlyTarget == target else { continue }
      guard selectedTargets?.contains(target) ?? true else { continue }
      guard projectEvidenceAllowed(target, projectID: projectID, cloud: cloud) else { continue }
      allowed.insert(target)
      let text = [task.title, task.detail, task.assignee].compactMap { $0 }.joined(separator: "\n")
      inputs.append(ProjectEvidenceInput(target: target, title: "タスク · \(task.title)", blocks: [ProjectSourceText(text: text)]))
    }
    if !cloud {
      for document in documents where document.spaceID == projectID {
        let target = ProjectCitation.Target.document(document.id)
        guard onlyTarget == nil || onlyTarget == target else { continue }
        guard selectedTargets?.contains(target) ?? true else { continue }
        allowed.insert(target)
        inputs.append(ProjectEvidenceInput(target: target, title: document.displayTitle, blocks: [ProjectSourceText(text: document.plainText)]))
      }
    }
    let sources = projectSources.filter { $0.projectID == projectID && $0.canProvideText }
    for source in sources {
      let target = ProjectCitation.Target.source(source.id)
      guard onlyTarget == nil || onlyTarget == target else { continue }
      guard selectedTargets?.contains(target) ?? true else { continue }
      guard projectEvidenceAllowed(target, projectID: projectID, cloud: cloud), let name = source.extractedTextReference else { continue }
      guard let blocks = try? await ProjectSourceTextReader.readAsync(name),
            self.source(id: source.id)?.extractedTextReference == name else { continue }
      guard !Task.isCancelled, currentTeamID == workspaceID, aiWorkspaceGeneration == generation,
            !isRestoring, !isStoreProtected else { return empty }
      guard projectEvidenceAllowed(target, projectID: projectID, cloud: cloud) else { continue }
      allowed.insert(target)
      inputs.append(ProjectEvidenceInput(target: target, title: source.title, blocks: blocks))
    }
    // Record photos have a local OCR index. Keep this evidence out of the FTS
    // snapshot shared with cloud requests, and index a bounded pending batch.
    var photoEntries: [MediaIndexEntry] = []
    if !cloud {
      let names = Set(records.filter { allowed.contains(.meeting($0.id)) }.flatMap { $0.photoFileNames ?? [] })
      if !names.isEmpty, reconcileMediaIndex() {
        await readPendingMediaText(for: names, limit: 6)
        guard !Task.isCancelled, aiWorkspaceGeneration == generation, currentTeamID == workspaceID else { return empty }
        photoEntries = mediaIndexEntries.filter { names.contains($0.name) && $0.textReadAt != nil && !$0.text.isEmpty }
      }
    }
    let currentAllowed = allowed.filter { projectEvidenceAllowed($0, projectID: projectID, cloud: cloud) }
    let permittedInputs = inputs.filter { currentAllowed.contains($0.target) }
    // A single-target read must not replace the full project's disposable index.
    let indexed: [ProjectEvidenceChunk]?
    if onlyTarget == nil, selectedTargets == nil {
      indexed = try? await ProjectSearchIndex.shared.retrieve(question: question, projectID: projectID, inputs: permittedInputs)
    } else { indexed = nil }
    guard !Task.isCancelled, currentTeamID == workspaceID, aiWorkspaceGeneration == generation,
          !isRestoring, !isStoreProtected else { return empty }
    let photos = photoEntries
    let context = await Task.detached(priority: .userInitiated) {
      let chunks = indexed ?? permittedInputs.flatMap { input in
        input.blocks.flatMap { block in
          ProjectContextBuilder.split(block.text, projectID: projectID, target: input.target,
            title: input.title, page: block.page, time: block.time, recordedAt: input.recordedAt)
        }
      }
      let photoChunks = photos.flatMap { entry -> [ProjectEvidenceChunk] in
        let target = ProjectCitation.Target.meeting(entry.recordID)
        guard currentAllowed.contains(target), let modifiedAt = entry.fileModifiedAt,
              let textReadAt = entry.textReadAt else { return [] }
        let reference = ProjectCitation.Photo(name: entry.name, byteCount: entry.byteCount,
          modifiedAt: modifiedAt, textReadAt: textReadAt)
        return ProjectContextBuilder.split(entry.text, projectID: projectID, target: target,
          title: entry.recordTitle, recordedAt: entry.recordDate, photo: reference)
      }
      return ProjectContextBuilder.build(question: question, projectID: projectID, chunks: chunks + photoChunks,
        allowed: Set(currentAllowed), characterBudget: budget, selectedTarget: onlyTarget)
    }.value
    guard !Task.isCancelled, currentTeamID == workspaceID, aiWorkspaceGeneration == generation,
          !isRestoring, !isStoreProtected else { return empty }
    return context
  }
}
