import Foundation

extension MemoraModel {
  func scheduleWidgetSnapshot() {
    guard MemoraWidgetSnapshotStore.fileURL != nil else { return }
    widgetSnapshotJob?.cancel()
    widgetSnapshotJob = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      await self?.refreshWidgetSnapshot()
    }
  }

  func refreshWidgetSnapshot() async {
    guard MemoraWidgetSnapshotStore.fileURL != nil else { return }
    let requestID = UUID()
    widgetSnapshotRequestID = requestID
    guard UserDefaults.standard.bool(forKey: "memora.widgets.enabled"), currentTeamID == nil,
          !isRestoring, !isStoreProtected, !AppLockService.isEnabled else {
      await WidgetSnapshotPublisher.shared.publish(nil)
      return
    }
    let now = Date.now
    var nextEvent: Date?
    if UserDefaults.standard.bool(forKey: "memora.widgets.calendarTime"), CalendarService.access == .granted {
      nextEvent = await CalendarService.events(on: now).filter { !$0.isAllDay && $0.start > now }.map(\.start).min()
    }
    guard !Task.isCancelled, widgetSnapshotRequestID == requestID, currentTeamID == nil,
          !isStoreProtected, !isRestoring, !AppLockService.isEnabled,
          UserDefaults.standard.bool(forKey: "memora.widgets.enabled") else { return }
    let todayRecords = meetings.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: now) }
    let memos = lifeLogEntries.filter { Calendar.current.isDate($0.occurredAt, inSameDayAs: now) && $0.meetingID == nil && ($0.kind == .memo || $0.kind == .photo) }
    let recordsByProject = Dictionary(grouping: meetings.compactMap { record in record.spaceID.map { ($0, record.createdAt) } }, by: { $0.0 })
    var openTasksByProject: [UUID: Int] = [:]
    var openTaskCount = 0
    for task in tasks where !task.isCompleted {
      openTaskCount += 1
      if let id = task.meetingID.flatMap({ meeting(id: $0)?.spaceID }) { openTasksByProject[id, default: 0] += 1 }
    }
    let visibleProjects: [MemoraWidgetSnapshot.Project] = UserDefaults.standard.bool(forKey: "memora.widgets.projectNames") ? spaces.prefix(20).map { project in
      .init(id: project.id, name: String(project.name.prefix(80)),
        openTaskCount: openTasksByProject[project.id, default: 0],
        lastRecordAt: recordsByProject[project.id]?.map { $0.1 }.max())
    } : []
    let snapshot = MemoraWidgetSnapshot(generatedAt: now, day: Calendar.current.startOfDay(for: now), openTaskCount: openTaskCount,
      recordCount: todayRecords.count + memos.count, nextEventAt: nextEvent, projects: visibleProjects)
    await WidgetSnapshotPublisher.shared.publish(snapshot)
  }
}
