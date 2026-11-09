import Foundation

// Sending finished summaries to other apps through webhooks, so a record can
// flow on to Slack, a CRM or a spreadsheet without copying it by hand.
extension MemoraModel {
  func saveWebhook(_ endpoint: WebhookEndpoint, url: String?) -> Bool {
    let originalAddress = KeychainStore.string(forKey: endpoint.keychainAccount)
    if let url {
      let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
      guard KeychainStore.set(trimmed, forKey: endpoint.keychainAccount) else { return false }
    }
    if webhookEndpoints.first(where: { $0.id == endpoint.id }) != endpoint
        || originalAddress != KeychainStore.string(forKey: endpoint.keychainAccount) {
      webhookResults[endpoint.id] = nil
    }
    if let index = webhookEndpoints.firstIndex(where: { $0.id == endpoint.id }) {
      webhookEndpoints[index] = endpoint
    } else {
      webhookEndpoints.append(endpoint)
    }
    return true
  }

  func deleteWebhook(_ id: UUID) {
    guard let endpoint = webhookEndpoints.first(where: { $0.id == id }) else { return }
    KeychainStore.set(nil, forKey: endpoint.keychainAccount)
    webhookEndpoints.removeAll { $0.id == id }
    webhookResults[id] = nil
  }

  /// Sends a finished summary to every enabled endpoint, in the background.
  func deliverSummaryToWebhooks(_ meetingID: UUID) {
    let enabled = webhookEndpoints.filter(\.isEnabled)
    guard !enabled.isEmpty, allowsRecordAccess(meetingID, purpose: .automaticWebhook),
          let meeting = meeting(id: meetingID) else { return }
    let meetingTasks = tasks(forMeeting: meetingID).filter { allowsTaskAccess($0, purpose: .automaticWebhook) }
    for endpoint in enabled {
      send(meeting, tasks: meetingTasks, to: endpoint, isTest: false)
    }
  }

  /// An explicit test uses only this prepared message, never a private record.
  func testWebhook(_ endpoint: WebhookEndpoint) {
    let sample = Meeting(
      id: UUID(), title: "テスト送信", createdAt: .now, duration: 0, source: .recording,
      status: .ready, summary: "Memoraからのテスト送信です。", keyPoints: [], decisions: [],
      openQuestions: [], transcript: [], spaceID: nil, audioURL: nil
    )
    send(sample, tasks: [], to: endpoint, isTest: true)
  }

  private func send(_ meeting: Meeting, tasks: [MemoraTask], to endpoint: WebhookEndpoint, isTest: Bool) {
    guard !Task.isCancelled else { return }
    guard let address = KeychainStore.string(forKey: endpoint.keychainAccount),
          let url = URL(string: address) else {
      webhookResults[endpoint.id] = WebhookResult(date: .now, succeeded: false, message: "URLが設定されていません。")
      return
    }
    let id = UUID()
    let job = WebhookDeliveryJob(endpoint: endpoint, address: address, workspaceID: currentTeamID,
      generation: aiWorkspaceGeneration, meeting: meeting, tasks: tasks, isTest: isTest)
    guard webhookDeliveryIsCurrent(job) else { return }
    let payload = WebhookDelivery.payload(for: meeting, tasks: tasks, format: endpoint.format, isTest: isTest)
    webhookDeliveries[id] = job
    latestWebhookDeliveryIDs[endpoint.id] = id
    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      defer {
        self.webhookDeliveries[id] = nil
        if self.latestWebhookDeliveryIDs[endpoint.id] == id { self.latestWebhookDeliveryIDs[endpoint.id] = nil }
      }
      guard self.webhookDeliveries[id] != nil, self.webhookDeliveryIsCurrent(job) else { return }
      let result = await WebhookDelivery.send(payload, to: url) { [weak self] in
        self?.webhookDeliveries[id] != nil && self?.webhookDeliveryIsCurrent(job) == true
      }
      guard !Task.isCancelled, self.latestWebhookDeliveryIDs[endpoint.id] == id,
            self.webhookDeliveries[id] != nil, self.webhookDeliveryIsCurrent(job) else { return }
      self.webhookResults[endpoint.id] = result
    }
    webhookDeliveries[id]?.task = task
  }

  /// Called synchronously by the state setters, so OFF then ON cannot revive
  /// a request that lost permission between those two changes.
  func invalidatePendingWebhookDeliveries() {
    for (id, job) in webhookDeliveries where !webhookDeliveryIsCurrent(job) {
      job.task?.cancel()
      webhookDeliveries[id] = nil
      if latestWebhookDeliveryIDs[job.endpoint.id] == id {
        latestWebhookDeliveryIDs[job.endpoint.id] = nil
        webhookResults[job.endpoint.id] = nil
      }
    }
  }

  private func webhookDeliveryIsCurrent(_ job: WebhookDeliveryJob) -> Bool {
    guard !isRestoring, !isStoreProtected, currentTeamID == job.workspaceID,
          aiWorkspaceGeneration == job.generation,
          webhookEndpoints.first(where: { $0.id == job.endpoint.id }) == job.endpoint,
          job.isTest || job.endpoint.isEnabled,
          KeychainStore.string(forKey: job.endpoint.keychainAccount) == job.address else { return false }
    if job.isTest { return true }
    return currentTeamID == nil && meeting(id: job.meeting.id) == job.meeting
      && allowsRecordAccess(job.meeting.id, purpose: .automaticWebhook)
      && tasks(forMeeting: job.meeting.id).filter { allowsTaskAccess($0, purpose: .automaticWebhook) } == job.tasks
  }
}
