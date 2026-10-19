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
            projectEvidenceAllowed(citation.target, projectID: projectID, cloud: cloud) else { return false }
      let text: String
      switch citation.target {
      case .source(let id):
        guard let name = source(id: id)?.extractedTextReference,
              let blocks = try? await ProjectSourceTextReader.readAsync(name),
              source(id: id)?.extractedTextReference == name else { return false }
        text = blocks.filter { citation.page == nil || $0.page == citation.page }.map(\.text).joined(separator: "\n")
      case .meeting(let id):
        guard let record = meeting(id: id) else { return false }
        text = ([record.summary] + record.transcript.map(\.text)).joined(separator: "\n")
      case .document(let id): text = document(id: id)?.plainText ?? ""
      case .task(let id):
        guard let task = self.task(id: id) else { return false }
        text = [task.title, task.detail, task.assignee].compactMap { $0 }.joined(separator: "\n")
      }
      guard !Task.isCancelled, currentTeamID == workspaceID, !citation.excerpt.isEmpty, text.contains(citation.excerpt),
            projectEvidenceAllowed(citation.target, projectID: projectID, cloud: cloud) else { return false }
    }
    return !Task.isCancelled && currentTeamID == workspaceID && !isRestoring && !isStoreProtected
  }

  func projectContext(question: String, projectID: UUID, cloud: Bool, budget: Int,
                      onlyTarget: ProjectCitation.Target? = nil,
                      selectedTargets: Set<ProjectCitation.Target>? = nil) async -> ProjectContextBuilder.Context {
    let workspaceID = currentTeamID
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
      blocks += record.transcript.map { ProjectSourceText(text: $0.text, time: $0.timestamp) }
      inputs.append(ProjectEvidenceInput(target: target, title: record.displayTitle, blocks: blocks))
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
      guard !Task.isCancelled, currentTeamID == workspaceID, !isRestoring, !isStoreProtected else { return empty }
      guard projectEvidenceAllowed(target, projectID: projectID, cloud: cloud) else { continue }
      allowed.insert(target)
      inputs.append(ProjectEvidenceInput(target: target, title: source.title, blocks: blocks))
    }
    let currentAllowed = allowed.filter { projectEvidenceAllowed($0, projectID: projectID, cloud: cloud) }
    let permittedInputs = inputs.filter { currentAllowed.contains($0.target) }
    // A single-target read must not replace the full project's disposable index.
    let indexed: [ProjectEvidenceChunk]?
    if onlyTarget == nil, selectedTargets == nil {
      indexed = try? await ProjectSearchIndex.shared.retrieve(question: question, projectID: projectID, inputs: permittedInputs)
    } else { indexed = nil }
    guard !Task.isCancelled, currentTeamID == workspaceID, !isRestoring, !isStoreProtected else { return empty }
    let context = await Task.detached(priority: .userInitiated) {
      let chunks = indexed ?? permittedInputs.flatMap { input in
        input.blocks.flatMap { block in
          ProjectContextBuilder.split(block.text, projectID: projectID, target: input.target,
            title: input.title, page: block.page, time: block.time)
        }
      }
      return ProjectContextBuilder.build(question: question, projectID: projectID, chunks: chunks,
        allowed: Set(currentAllowed), characterBudget: budget, selectedTarget: onlyTarget)
    }.value
    guard !Task.isCancelled, currentTeamID == workspaceID, !isRestoring, !isStoreProtected else { return empty }
    return context
  }
}
