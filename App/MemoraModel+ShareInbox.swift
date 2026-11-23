import Foundation

extension MemoraModel {
  func refreshShareInbox() async {
    guard let root = ShareInboxConfiguration.root else { return }
    let queue = ShareInboxQueue(root: root)
    do {
      let projects = currentTeamID == nil ? (recentProjects + spaces.filter { !recentProjectIDs.contains($0.id) }) : []
      try await queue.updateProjects(projects.map { ShareInboxProject(id: $0.id, name: String($0.name.prefix(200))) })
      try await queue.clearAbandonedDrafts()
    } catch { shareInboxFailure = error.localizedDescription }
    await importShareInbox()
  }

  func importShareInbox(requestID: UUID? = nil, projectID replacement: UUID? = nil) async {
    guard !isRestoring, isStoreWritable(), !isImportingShareInbox, currentTeamID == nil,
          let root = ShareInboxConfiguration.root else { return }
    isImportingShareInbox = true
    defer { isImportingShareInbox = false }
    let queue = ShareInboxQueue(root: root)
    do {
      let inspection = try await queue.inspect()
      let requests = inspection.requests
      shareInboxRejectedIDs = inspection.invalidIDs
      if !inspection.invalidIDs.isEmpty { shareInboxFailure = "読み込めない共有が保管されています。設定の「共有からの取り込み」で確認してください。" }
      for request in requests where requestID == nil || request.id == requestID {
        let projectID = replacement ?? request.projectID
        guard space(id: projectID) != nil else {
          shareInboxFailure = "共有の保存先が見つかりません。設定の「共有からの取り込み」で保存先を選び直してください。内容は保管されています。"
          continue
        }
        var complete = true
        for item in request.items {
          do { try await importShareItem(item, requestID: request.id, projectID: projectID, queue: queue) }
          catch { shareInboxFailure = error.localizedDescription; complete = false; break }
        }
        if complete {
          try await queue.remove(request.id)
          for item in request.items { try? localStore.remove(sharedPDFReceiptKey(item.id)) }
        }
      }
      let remaining = try await queue.inspect()
      shareInboxRequests = remaining.requests
      shareInboxRejectedIDs = remaining.invalidIDs
      if shareInboxRequests.isEmpty && shareInboxRejectedIDs.isEmpty { shareInboxFailure = nil }
    } catch { shareInboxFailure = error.localizedDescription }
  }

  func discardShareRequest(_ id: UUID) async {
    guard !isImportingShareInbox, let root = ShareInboxConfiguration.root else { return }
    let queue = ShareInboxQueue(root: root)
    do {
      let discardedItems = shareInboxRequests.first(where: { $0.id == id })?.items ?? []
      try await queue.remove(id)
      for item in discardedItems { try? localStore.remove(sharedPDFReceiptKey(item.id)) }
      let remaining = try await queue.inspect()
      shareInboxRequests = remaining.requests
      shareInboxRejectedIDs = remaining.invalidIDs
      if shareInboxRequests.isEmpty && shareInboxRejectedIDs.isEmpty { shareInboxFailure = nil }
    } catch { shareInboxFailure = error.localizedDescription }
  }

  private func importShareItem(_ item: ShareInboxItem, requestID: UUID, projectID: UUID, queue: ShareInboxQueue) async throws {
    guard let context = LocalImportContext(projectID: projectID, in: self) else { throw ShareInboxQueue.Failure.invalid }
    // A retry after SQLite committed but before the queue was removed sees the
    // same item identity. It does not create another source or undo a detach.
    if source(id: item.id) != nil { return }
    switch localStore.readOutcome(sharedPDFReceiptKey(item.id)) {
    case .data(let data):
      guard let receipt = try? JSONDecoder().decode([String: String].self, from: data),
            receipt["requestID"] == requestID.uuidString, receipt["itemID"] == item.id.uuidString,
            let rawIDs = receipt["sourceIDs"], rawIDs.utf8.count <= 3_699 else {
        throw ShareInboxQueue.Failure.invalid
      }
      let parts = rawIDs.split(separator: ",", omittingEmptySubsequences: false)
      let ids = parts.compactMap { UUID(uuidString: String($0)) }
      guard !ids.isEmpty, ids.count <= 100, ids.count == parts.count,
            Set(ids).count == ids.count else { throw ShareInboxQueue.Failure.invalid }
      // Restore can remove a whole newly imported group while its queue entry
      // survives. A receipt without any remaining source must not discard it.
      if ids.contains(where: { source(id: $0) != nil }) { return }
    case .failed: throw ShareInboxQueue.Failure.invalid
    case .missing: break
    }
    let intent: CaptureIntent
    switch item.kind {
    case .link:
      guard let url = URL(string: item.value) else { throw ShareInboxQueue.Failure.invalid }
      intent = .url(url)
    case .text:
      intent = .note(item.value)
    case .file:
      let file = try await queue.file(item.value, requestID: requestID)
      if try PDFSourcePartitioning.requiresPartition(file) {
        let partition = try await PDFSourcePartitioning.prepare(file)
        defer { partition.cleanup() }
        guard let ids = try await importPDFParts(partition, context: context,
          sourceTitle: item.title.isEmpty ? nil : item.title, registrationReceipt: { ids in
            (key: self.sharedPDFReceiptKey(item.id), data: try JSONEncoder().encode(
              ["requestID": requestID.uuidString, "itemID": item.id.uuidString,
               "sourceIDs": ids.map(\.uuidString).joined(separator: ",")]))
          }), !ids.isEmpty else {
          throw ShareInboxQueue.Failure.invalid
        }
        return
      }
      intent = .file(file)
    }
    let outcome = await capture(intent, context: context, sourceID: item.id,
      metadata: ["shareRequestID": requestID.uuidString], title: item.title)
    switch outcome {
    case .imported, .duplicate:
      return
    case .refused(let message):
      if message.isEmpty { throw ShareInboxQueue.Failure.invalid }
      throw NSError(domain: "Memora.ShareInbox", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
  }

  private func sharedPDFReceiptKey(_ itemID: UUID) -> String {
    "memora.share.pdfReceipt." + itemID.uuidString
  }
}
