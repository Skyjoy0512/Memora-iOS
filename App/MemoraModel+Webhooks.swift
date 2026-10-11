import Foundation

// Sending finished summaries to other apps through webhooks, so a record can
// flow on to Slack, a CRM or a spreadsheet without copying it by hand.
extension MemoraModel {
  func saveWebhook(_ endpoint: WebhookEndpoint, url: String?) -> Bool {
    if let url {
      let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
      guard KeychainStore.set(trimmed, forKey: endpoint.keychainAccount) else { return false }
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
    let meetingTasks = tasks(forMeeting: meetingID)
    for endpoint in enabled {
      send(meeting, tasks: meetingTasks, to: endpoint, isTest: false)
    }
  }

  /// Sends the newest summarised record, or a placeholder, to check an endpoint.
  func testWebhook(_ endpoint: WebhookEndpoint) {
    let sample = Meeting(
      id: UUID(), title: "テスト送信", createdAt: .now, duration: 0, source: .recording,
      status: .ready, summary: "Memoraからのテスト送信です。", keyPoints: [], decisions: [],
      openQuestions: [], transcript: [], spaceID: nil, audioURL: nil
    )
    send(sample, tasks: [], to: endpoint, isTest: true)
  }

  private func send(_ meeting: Meeting, tasks: [MemoraTask], to endpoint: WebhookEndpoint, isTest: Bool) {
    guard let address = KeychainStore.string(forKey: endpoint.keychainAccount),
          let url = URL(string: address) else {
      webhookResults[endpoint.id] = WebhookResult(date: .now, succeeded: false, message: "URLが設定されていません。")
      return
    }
    let payload = WebhookDelivery.payload(for: meeting, tasks: tasks, format: endpoint.format, isTest: isTest)
    Task { @MainActor [weak self] in
      guard isTest || self?.allowsRecordAccess(meeting.id, purpose: .automaticWebhook) == true else { return }
      let result = await WebhookDelivery.send(payload, to: url)
      self?.webhookResults[endpoint.id] = result
    }
  }
}
