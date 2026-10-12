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
        if complete { try await queue.remove(request.id) }
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
      try await queue.remove(id)
      let remaining = try await queue.inspect()
      shareInboxRequests = remaining.requests
      shareInboxRejectedIDs = remaining.invalidIDs
      if shareInboxRequests.isEmpty && shareInboxRejectedIDs.isEmpty { shareInboxFailure = nil }
    } catch { shareInboxFailure = error.localizedDescription }
  }

  private func importShareItem(_ item: ShareInboxItem, requestID: UUID, projectID: UUID, queue: ShareInboxQueue) async throws {
    guard !isRestoring, currentTeamID == nil, space(id: projectID) != nil else { throw ShareInboxQueue.Failure.invalid }
    // A retry after SQLite committed but before the queue was removed sees the
    // same item identity. It does not create another source or undo a detach.
    if source(id: item.id) != nil { return }
    var source = ProjectSource(projectID: projectID, kind: .note, title: item.title)
    source.id = item.id
    source.metadata = ["shareRequestID": requestID.uuidString]
    var created: [String] = []
    do {
      switch item.kind {
      case .link:
        let link = try ProjectSourceURL.normalized(item.value)
        if projectSources.contains(where: { $0.projectID == projectID && $0.originalURL == link.url }) { return }
        source.kind = link.kind
        source.originalURL = link.url
        if source.title.isEmpty { source.title = link.url.host ?? "Webリンク" }
      case .text:
        let text = try JSONEncoder().encode([ProjectSourceText(text: item.value)])
        let name = try await ProjectSourceFiles.shared.write(text, extension: "json")
        created.append(name)
        source.extractedTextReference = name
        source.processingStatus = .ready
      case .file:
        let file = try await queue.file(item.value, requestID: requestID)
        let receipt = try await ProjectSourceFiles.shared.copy(file)
        created.append(receipt.reference)
        if projectSources.contains(where: { $0.projectID == projectID && $0.contentFingerprint == receipt.fingerprint }) {
          await ProjectSourceFiles.shared.remove(created); return
        }
        let suffix = file.pathExtension.lowercased()
        source.kind = suffix == "pdf" ? .pdf : ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff"].contains(suffix) ? .image :
          ["m4a", "mp3", "wav", "aiff", "caf", "flac", "ogg"].contains(suffix) ? .audio : .document
        source.localFileReference = receipt.reference
        source.contentFingerprint = receipt.fingerprint
      }
      guard !isRestoring, currentTeamID == nil, space(id: projectID) != nil, storeProjectSource(source) else { throw ShareInboxQueue.Failure.invalid }
      if source.kind != .note { Task { await prepareProjectSource(source.id) } }
    } catch { await ProjectSourceFiles.shared.remove(created); throw error }
  }
}
