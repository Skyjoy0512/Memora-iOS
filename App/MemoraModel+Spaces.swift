import Foundation

extension MemoraModel {
  var visibleProjectID: UUID? {
    let id: UUID?
    if case .projectSource(let sourceID) = activeNavigationPath.last {
      id = source(id: sourceID)?.projectID
    } else if case .projectPDF(let sourceID, _) = activeNavigationPath.last {
      id = source(id: sourceID)?.projectID
    } else if case .projectChat(let chatID) = activeNavigationPath.last {
      id = projectChat(id: chatID)?.projectID
    } else {
      id = RootNavigation.projectID(in: activeNavigationPath)
    }
    return ProjectFiling.existingProject(id, in: spaces)
  }

  var recentProjects: [MemoraSpace] {
    let byID = Dictionary(spaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return recentProjectIDs.compactMap { byID[$0] }
  }

  func noteProjectUsed(_ id: UUID) {
    guard space(id: id) != nil else { return }
    let updated = Array(([id] + recentProjectIDs.filter { $0 != id }).prefix(8))
    guard updated != recentProjectIDs else { return }
    recentProjectIDs = updated
    UserDefaults.standard.set(updated.map(\.uuidString), forKey: "memora.projects.recentIDs")
  }

  /// Returns the new project's id so the caller can open it.
  @discardableResult
  func addSpace(name: String) -> UUID? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !isRestoring, currentTeamID == nil, isStoreWritable(), !trimmed.isEmpty else { return nil }
    let space = MemoraSpace(id: UUID(), name: trimmed, symbol: "folder")
    let candidate = [space] + spaces
    guard persistNow(candidate, forKey: StorageKey.spaces) else { return nil }
    spaces = candidate
    return space.id
  }

  @discardableResult
  func renameSpace(_ id: UUID, name: String) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !isRestoring, currentTeamID == nil, isStoreWritable(), !trimmed.isEmpty,
          let index = spaces.firstIndex(where: { $0.id == id }) else { return false }
    var candidate = spaces
    candidate[index].name = trimmed
    guard persistNow(candidate, forKey: StorageKey.spaces) else { return false }
    spaces = candidate
    return true
  }

  /// Removes a project. Its records are kept and become uncategorized.
  @discardableResult
  func deleteSpace(_ id: UUID) -> Bool {
    guard !isRestoring, currentTeamID == nil, isStoreWritable(), spaces.contains(where: { $0.id == id }) else { return false }
    let candidateSpaces = spaces.filter { $0.id != id }
    var candidateMeetings = meetings
    for index in candidateMeetings.indices where candidateMeetings[index].spaceID == id {
      candidateMeetings[index].spaceID = nil
    }
    var candidateDocuments = documents
    for index in candidateDocuments.indices where candidateDocuments[index].spaceID == id {
      candidateDocuments[index].spaceID = nil
    }
    let candidateSources = projectSources.map { source in
      var value = source
      if value.projectID == id { value.projectID = nil }
      return value
    }
    let candidateChats = projectChats.map { thread in
      var value = thread
      if value.projectID == id {
        value.projectID = nil
        value.pendingMessageID = nil
      }
      return value
    }
    guard persistBatch({
      [
        (key: StorageKey.projectSources, data: try RecordStore.encoded(candidateSources)),
        (key: StorageKey.projectChats, data: try RecordStore.encoded(candidateChats)),
        (key: StorageKey.spaces, data: try RecordStore.encoded(candidateSpaces)),
        (key: StorageKey.meetings, data: try RecordStore.encoded(candidateMeetings)),
        (key: StorageKey.documents, data: try RecordStore.encoded(candidateDocuments))
      ]
    }) else { return false }
    projectSources = candidateSources
    Task { try? await ProjectSearchIndex.shared.remove(projectID: id) }
    for thread in projectChats where thread.projectID == id { projectChatJobs[thread.id]?.cancel() }
    projectChats = candidateChats
    spaces = candidateSpaces
    meetings = candidateMeetings
    documents = candidateDocuments
    meetingSearchTexts.removeAll()
    return true
  }

  /// Files a record under a project, or takes it out of every project.
  @discardableResult
  func setSpace(_ spaceID: UUID?, forMeeting meetingID: UUID) -> Bool {
    moveMeetings([meetingID], to: spaceID)
  }

  /// Files several records under one project, or under none, in a single write.
  @discardableResult
  func moveMeetings(_ ids: Set<UUID>, to spaceID: UUID?) -> Bool {
    guard !isRestoring, currentTeamID == nil, isStoreWritable() else { return false }
    guard let candidate = ProjectFiling.moving(ids, to: spaceID, meetings: meetings, spaces: spaces) else {
      persistenceFailureMessage = "移動するファイルか移動先のプロジェクトが見つかりません。選び直してください。"
      return false
    }
    guard meetings.contains(where: { ids.contains($0.id) && $0.spaceID != spaceID }) else { return true }

    let stored = persistBatch {
      [(key: StorageKey.meetings, data: try RecordStore.encoded(candidate))]
    }
    guard stored else { return false }
    for id in ids { meetingSearchTexts.removeValue(forKey: id) }
    invalidateProjectEvidence(ids.map(ProjectCitation.Target.meeting) + tasks.filter { $0.meetingID.map(ids.contains) == true }.map { .task($0.id) })
    meetings = candidate
    announce(spaceID.flatMap { space(id: $0)?.name }.map { "\($0)へ移動しました" } ?? "未分類へ移動しました")
    return true
  }
}
