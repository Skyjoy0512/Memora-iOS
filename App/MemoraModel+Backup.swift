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
    let selected = meetings.filter { meetingIDs.contains($0.id) }
    guard !selected.isEmpty else { throw TeamShareError.empty }
    guard selected.allSatisfy({ allowsRecordAccess($0.id, purpose: .teamSharing) }) else {
      throw TeamShareError.privacyRestricted
    }

    // Try once more to write any inline photos, so the package carries files.
    materializePendingLegacyPhotos()

    let spaces = self.spaces.filter { space in
      selected.contains { $0.spaceID == space.id }
    }
    let tasks = self.tasks.filter { ($0.meetingID.map(meetingIDs.contains) ?? false) && allowsTaskAccess($0, purpose: .teamSharing) }
    let lifeLogEntries = self.lifeLogEntries.filter {
      ($0.meetingID.map(meetingIDs.contains) ?? false) && allowsJournalAccess($0, purpose: .teamSharing)
    }.map { original in
      var entry = original
      entry.latitude = nil
      entry.longitude = nil
      entry.locationName = nil
      return entry
    }
    let participantIDs = Set(selected.compactMap(\.participantIDs).flatMap { $0 })
    let people = self.people.filter { participantIDs.contains($0.id) }

    return try await Task.detached(priority: .userInitiated) {
      try BackupPackage.write(
        meetings: selected,
        spaces: spaces,
        tasks: tasks,
        lifeLogEntries: lifeLogEntries,
        people: people,
        aiHistory: [],
        into: FileManager.default.temporaryDirectory
      )
    }.value
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
    await cloudSharing.refreshAvailability()
    if let message = cloudSharing.availabilityMessage {
      cloudShareMessage = message
      return
    }
    do {
      guard snapshot.meetings.allSatisfy({ allowsRecordAccess($0.id, purpose: .teamSharing) }),
            snapshot.tasks.allSatisfy({ allowsRecordAccess(.task($0.id), purpose: .teamSharing) }) else {
        throw TeamShareError.privacyRestricted
      }
      let payload = try RecordStore.encoded(snapshot)
      pendingCloudShare = try await cloudSharing.makeShare(
        title: title,
        kind: snapshot.kind.rawValue,
        payload: payload,
        ownerName: profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    } catch {
      cloudShareMessage = "共有を開始できませんでした。\(error.localizedDescription)"
    }
  }

  /// Restores a package. It refuses to run when this device already holds
  /// records, so a backup can never silently replace them. The package is
  /// checked and its media put in place off the main actor; only the records are
  /// applied here, once every file is confirmed.
  func restoreBackup(from packageURL: URL) async throws {
    guard currentTeamID == nil else { throw BackupPackage.BackupError.personalWorkspaceRequired }
    // A store that could not be read must not be written over, and nothing may
    // be in flight.
    guard !isStoreProtected else { throw BackupPackage.BackupError.storeProtected }
    guard !isRecording, !isSavingCapture, recordingDraft == nil else {
      throw BackupPackage.BackupError.busy
    }
    guard !isRestoring, !isImportingShareInbox, !isAIChatResponding, residentJobs.isEmpty,
          projectChatJobs.isEmpty, webResearchJobs.isEmpty, processing.activeIDs.isEmpty, speakerAnalysisIDs.isEmpty,
          !isEnrollingSpeaker else { throw BackupPackage.BackupError.busy }
    guard isEmpty else { throw BackupPackage.BackupError.notEmpty }

    // Held for the whole restore, so the model refuses changes that could add a
    // record while the package is being prepared off the main actor.
    isRestoring = true
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
      let stored = persistBatch {
        [
          (key: StorageKey.meetings, data: try RecordStore.encoded(manifest.meetings)),
          (key: StorageKey.spaces, data: try RecordStore.encoded(manifest.spaces)),
          (key: StorageKey.tasks, data: try RecordStore.encoded(manifest.tasks)),
          (key: StorageKey.lifeLogEntries, data: try RecordStore.encoded(manifest.lifeLogEntries)),
          (key: StorageKey.people, data: try RecordStore.encoded(manifest.people)),
          (key: StorageKey.aiHistory, data: try RecordStore.encoded(manifest.aiHistory)),
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
      aiHistory = manifest.aiHistory
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
