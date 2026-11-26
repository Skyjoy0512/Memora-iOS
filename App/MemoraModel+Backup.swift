import Foundation

extension MemoraModel {
  /// Writes any inline photos older records still hold, so nothing is left in the
  /// bytes-and-names in-between state before a save. Failures are left alone for
  /// the load-time message to report.
  private func materializePendingLegacyPhotos() {
    guard meetings.contains(where: { $0.legacyPhotoData != nil }) else { return }
    var materialized = meetings
    var changed = false
    for index in materialized.indices where materialized[index].legacyPhotoData != nil {
      if materialized[index].materializeLegacyPhotos() {
        changed = true
      }
    }
    if changed {
      meetings = materialized
    }
  }



  /// True when a restore would not overwrite anything of the person's own. It
  /// counts the trash, unfinished drafts, and real AI history as well as the
  /// records, so a restore cannot quietly discard something that is only out of
  /// sight. The seed sample is not counted.
  var isEmpty: Bool {
    meetings.isEmpty
      && spaces.isEmpty
      && documents.isEmpty
      && aiMemories.isEmpty
      && companyTemplates.isEmpty
      && mailDrafts.isEmpty
      && projectSources.isEmpty
      && projectChats.isEmpty
      && customSkills.isEmpty
      && webResearchReports.isEmpty
      && tasks.isEmpty
      && lifeLogEntries.isEmpty
      && people.isEmpty
      && trashedRecords.isEmpty
      && trashedLifeLogEntries.isEmpty
      && recordingDraft == nil
      && composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !aiHistory.contains { $0.id != Self.seedAIHistoryID }
  }

  /// Writes a versioned package of the records and their media, off the main
  /// actor so the screen stays responsive while the files are copied.
  func makeBackupPackage() async throws -> URL {
    guard currentTeamID == nil else { throw BackupPackage.BackupError.personalWorkspaceRequired }
    // Try once more to write any inline photos an older record still holds, so
    // the package carries files instead of bytes a restore would refuse.
    materializePendingLegacyPhotos()
    let meetings = self.meetings
    let spaces = self.spaces
    let tasks = self.tasks
    let lifeLogEntries = self.lifeLogEntries
    let people = self.people
    let aiHistory = self.aiHistory
    let mailDrafts = self.mailDrafts
    let aiMemories = self.aiMemories
    let companyTemplates = self.companyTemplates
    let documents = self.documents
    let projectSources = self.projectSources
    let projectChats = self.projectChats
    let webResearchReports = self.webResearchReports
    let customSkills = self.customSkills
    let skillSelections = skillLastSelectedAt.map { SkillSelection(skillID: $0.key, selectedAt: $0.value) }
    return try await Task.detached(priority: .userInitiated) {
      try BackupPackage.write(
        meetings: meetings,
        spaces: spaces,
        tasks: tasks,
        lifeLogEntries: lifeLogEntries,
        people: people,
        aiHistory: aiHistory,
        aiMemories: aiMemories,
        mailDrafts: mailDrafts,
        companyTemplates: companyTemplates,
        documents: documents,
        projectSources: projectSources,
        projectChats: projectChats,
        webResearchReports: webResearchReports,
        customSkills: customSkills,
        skillSelections: skillSelections,
        into: FileManager.default.temporaryDirectory
      )
    }.value
  }

  /// Writes a package of just the chosen records, for handing to a teammate.
  /// Team plan only. It carries the records' audio, photos, tasks and journal
  /// entries, but no AI history and no settings. The teammate still needs an
  /// empty library to restore it, since merging packages is not built yet.
  func makeTeamSharePackage(meetingIDs: Set<UUID>) async throws -> URL {
    guard hasTeamPlan else { throw TeamShareError.requiresTeamPlan }
    guard !meetingIDs.isEmpty else { throw TeamShareError.empty }
    guard meetingIDs.allSatisfy({ allowsRecordAccess($0, purpose: .teamSharing) }) else {
      throw TeamShareError.privacyRestricted
    }

    // Try once more to write any inline photos, so the package carries files.
    materializePendingLegacyPhotos()

    let generation = aiWorkspaceGeneration
    let workspace = currentTeamID
    let selected = meetings.filter { meetingIDs.contains($0.id) }
    // Meeting sharing does not grant permission to export the person's record.
    let sharedMeetings = selected.map { original in
      var meeting = original
      meeting.participantIDs = nil
      return meeting
    }
    let spaces = self.spaces.filter { space in
      selected.contains { $0.spaceID == space.id }
    }
    let tasks = self.tasks.filter { ($0.meetingID.map(meetingIDs.contains) ?? false) && allowsTaskAccess($0, purpose: .teamSharing) }
    let journal = self.lifeLogEntries.filter {
      ($0.meetingID.map(meetingIDs.contains) ?? false) && allowsJournalAccess($0, purpose: .teamSharing)
    }
    let lifeLogEntries = journal.map { original in
      var entry = original
      entry.latitude = nil
      entry.longitude = nil
      entry.locationName = nil
      entry.personIDs = []
      return entry
    }

    let package = try await Task.detached(priority: .userInitiated) {
      try BackupPackage.write(
        meetings: sharedMeetings,
        spaces: spaces,
        tasks: tasks,
        lifeLogEntries: lifeLogEntries,
        people: [],
        aiHistory: [],
        into: FileManager.default.temporaryDirectory
      )
    }.value
    guard !Task.isCancelled, hasTeamPlan,
          aiWorkspaceGeneration == generation, currentTeamID == workspace,
          meetings.filter({ meetingIDs.contains($0.id) }) == selected,
          selected.allSatisfy({ allowsRecordAccess($0.id, purpose: .teamSharing) }),
          self.spaces.filter({ space in selected.contains { $0.spaceID == space.id } }) == spaces,
          self.tasks.filter({ ($0.meetingID.map(meetingIDs.contains) ?? false) && allowsTaskAccess($0, purpose: .teamSharing) }) == tasks,
          self.lifeLogEntries.filter({ ($0.meetingID.map(meetingIDs.contains) ?? false) && allowsJournalAccess($0, purpose: .teamSharing) }) == journal else {
      try? FileManager.default.removeItem(at: package)
      throw TeamShareError.privacyRestricted
    }
    return package
  }

  /// Shares a project with the team through CloudKit. Team plan only.
  func shareSpaceWithTeam(_ id: UUID) async {
    guard let space = space(id: id) else { return }
    let inProject = meetings.filter { $0.spaceID == id }
    guard inProject.allSatisfy({ allowsRecordAccess($0.id, purpose: .teamSharing) }) else {
      cloudShareMessage = RecordAccessPolicy.refusal
      return
    }
    let projectTasks = tasks.filter { task in inProject.contains { $0.id == task.meetingID } && allowsTaskAccess(task, purpose: .teamSharing) }
    let snapshot = TeamShareSnapshot(kind: .project, space: space, meetings: inProject, tasks: projectTasks)
    await beginCloudShare(title: space.name, snapshot: snapshot)
  }

  /// Shares a single record with the team through CloudKit. Team plan only.
  func shareMeetingWithTeam(_ id: UUID) async {
    guard let meeting = meeting(id: id) else { return }
    guard allowsRecordAccess(id, purpose: .teamSharing) else {
      cloudShareMessage = RecordAccessPolicy.refusal
      return
    }
    let parentSpace = meeting.spaceID.flatMap { space(id: $0) }
    let meetingTasks = tasks.filter { $0.meetingID == id && allowsTaskAccess($0, purpose: .teamSharing) }
    let snapshot = TeamShareSnapshot(
      kind: .meeting,
      space: parentSpace,
      meetings: [meeting],
      tasks: meetingTasks
    )
    await beginCloudShare(title: meeting.displayTitle, snapshot: snapshot)
  }

  /// Publishes a snapshot and asks the system to invite people. It reports the
  /// plan, iCloud, and save state rather than starting a share that cannot work.
  private func beginCloudShare(title: String, snapshot: TeamShareSnapshot) async {
    guard hasTeamPlan else {
      cloudShareMessage = "チーム共有はチームプランで利用できます。設定の「プラン」から選べます。"
      return
    }
    guard !cloudSharing.isWorking, cloudSharePreparation == nil else {
      cloudShareMessage = "共有の準備中です。完了するまでお待ちください。"
      return
    }
    let preparation = CloudSharePreparation(workspaceID: currentTeamID, generation: aiWorkspaceGeneration,
      snapshot: snapshot, ownerName: profile.name.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !Task.isCancelled, cloudSharePreparationIsCurrent(preparation) else {
      cloudShareMessage = RecordAccessPolicy.refusal
      return
    }
    cloudSharePreparation = preparation
    defer {
      if cloudSharePreparation?.id == preparation.id { cloudSharePreparation = nil }
      if cloudShareTask?.id == preparation.id { cloudShareTask = nil }
    }
    await cloudSharing.refreshAvailability()
    guard cloudSharePreparation?.id == preparation.id, !Task.isCancelled,
          cloudSharePreparationIsCurrent(preparation) else { return }
    if let message = cloudSharing.availabilityMessage {
      cloudShareMessage = message
      return
    }
    do {
      let payload = try RecordStore.encoded(snapshot)
      let service = cloudSharing
      let operation = Task { @MainActor [weak self] in
        try await service.makeShare(title: title, kind: snapshot.kind.rawValue, payload: payload,
          ownerName: preparation.ownerName) { [weak self] in
          self?.cloudSharePreparation?.id == preparation.id
            && self?.cloudSharePreparationIsCurrent(preparation) == true
        }
      }
      cloudShareTask = (preparation.id, operation)
      let request = try await withTaskCancellationHandler {
        try await operation.value
      } onCancel: { operation.cancel() }
      guard !Task.isCancelled, cloudSharePreparation?.id == preparation.id,
            cloudSharePreparationIsCurrent(preparation) else {
        try await cloudSharing.discardUnpublishedShare(request)
        return
      }
      pendingCloudShare = request
    } catch {
      if cloudSharePreparation?.id == preparation.id || (error as? CloudSharingError) == .cleanupFailed {
        cloudShareMessage = "共有を開始できませんでした。\(error.localizedDescription)"
      }
    }
  }

  func invalidatePendingCloudShare() {
    guard let preparation = cloudSharePreparation, !cloudSharePreparationIsCurrent(preparation) else { return }
    if cloudShareTask?.id == preparation.id { cloudShareTask?.task.cancel() }
    cloudSharePreparation = nil
    cloudShareMessage = "設定や共有する内容が変わったため、共有の準備を中止しました。"
  }

  private func cloudSharePreparationIsCurrent(_ preparation: CloudSharePreparation) -> Bool {
    let snapshot = preparation.snapshot
    guard !isRestoring, !isStoreProtected, currentTeamID == nil, hasTeamPlan,
          currentTeamID == preparation.workspaceID, aiWorkspaceGeneration == preparation.generation,
          profile.name.trimmingCharacters(in: .whitespacesAndNewlines) == preparation.ownerName,
          snapshot.meetings.allSatisfy({ meeting(id: $0.id) == $0 && allowsRecordAccess($0.id, purpose: .teamSharing) }) else { return false }
    if snapshot.kind == .project {
      guard let project = snapshot.space, space(id: project.id) == project,
            meetings.filter({ $0.spaceID == project.id }) == snapshot.meetings else { return false }
    } else {
      guard snapshot.meetings.count == 1,
            snapshot.meetings[0].spaceID.flatMap({ space(id: $0) }) == snapshot.space else { return false }
    }
    let ids = Set(snapshot.meetings.map(\.id))
    return tasks.filter { $0.meetingID.map(ids.contains) == true && allowsTaskAccess($0, purpose: .teamSharing) } == snapshot.tasks
  }

  /// Restores a package. It refuses to run when this device already holds
  /// records, so a backup can never silently replace them. The package is
  /// checked and its media put in place off the main actor; only the records are
  /// applied here, once every file is confirmed.
  func restoreBackup(from packageURL: URL) async throws {
    try beginBackupRestore()
    defer { isRestoring = false }

    let generation = aiWorkspaceGeneration
    let workspace = currentTeamID
    try await BackupRestoreTransaction.restore(from: packageURL) { manifest in
      guard self.aiWorkspaceGeneration == generation, self.currentTeamID == workspace else {
        throw CancellationError()
      }
      guard !self.isStoreProtected else { throw BackupPackage.BackupError.storeProtected }
      guard self.isEmpty else { throw BackupPackage.BackupError.notEmpty }

      // The records go in as one write. If it fails, only the files this restore
      // just created are taken back, so the device is left as it was.
      let restoredHistory = manifest.aiHistory.map(\.withoutCloudReplayAuthorization)
      let stored = persistBatch {
        [
          (key: StorageKey.meetings, data: try RecordStore.encoded(manifest.meetings)),
          (key: StorageKey.spaces, data: try RecordStore.encoded(manifest.spaces)),
          (key: StorageKey.tasks, data: try RecordStore.encoded(manifest.tasks)),
          (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(manifest.lifeLogEntries)),
          (key: StorageKey.people, data: try RecordStore.encoded(manifest.people)),
          (key: StorageKey.aiHistory, data: try RecordStore.encoded(restoredHistory)),
          (key: StorageKey.aiMemories, data: try RecordStore.encoded(manifest.aiMemories ?? aiMemories)),
          (key: "memora.mailDrafts.v1", data: try RecordStore.encoded(manifest.mailDrafts ?? mailDrafts)),
          (key: "memora.companyTemplates.v1", data: try RecordStore.encoded(manifest.companyTemplates ?? companyTemplates)),
          (key: StorageKey.documents, data: try RecordStore.encoded(manifest.documents ?? [])),
          (key: StorageKey.projectSources, data: try RecordStore.encoded(manifest.projectSources ?? [])),
          (key: StorageKey.projectChats, data: try RecordStore.encoded(manifest.projectChats ?? [])),
          (key: "memora.webResearch.v1", data: try RecordStore.encoded(manifest.webResearchReports ?? [])),
          (key: StorageKey.customSkills, data: try RecordStore.encoded(manifest.customSkills ?? [])),
          (key: StorageKey.skillUsage, data: try RecordStore.encoded(manifest.skillSelections ?? []))
        ]
      }
      guard stored else {
        throw BackupPackage.BackupError.storeWriteFailed
      }

      meetings = manifest.meetings
      spaces = manifest.spaces
      tasks = manifest.tasks
      lifeLogEntries = manifest.lifeLogEntries
      people = manifest.people
      aiHistory = restoredHistory
      aiMemories = manifest.aiMemories ?? aiMemories
      companyTemplates = manifest.companyTemplates ?? companyTemplates
      mailDrafts = manifest.mailDrafts ?? mailDrafts
      documents = manifest.documents ?? []
      projectSources = manifest.projectSources ?? []
      projectChats = manifest.projectChats ?? []
      webResearchReports = manifest.webResearchReports ?? []
      customSkills = manifest.customSkills ?? []
      skillLastSelectedAt = Dictionary((manifest.skillSelections ?? []).map { ($0.skillID, $0.selectedAt) }, uniquingKeysWith: max)
    }
  }
}
