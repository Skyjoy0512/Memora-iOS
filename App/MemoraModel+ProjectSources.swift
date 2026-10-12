import Foundation

extension MemoraModel {
  func source(id: UUID) -> ProjectSource? { projectSources.first { $0.id == id } }

  @discardableResult
  func addProjectLink(_ input: String, projectID: UUID) throws -> UUID? {
    guard !isRestoring, space(id: projectID) != nil else { return nil }
    let link = try ProjectSourceURL.normalized(input)
    if let existing = projectSources.first(where: { $0.projectID == projectID && $0.originalURL == link.url }) {
      return existing.id
    }
    let source = ProjectSource(projectID: projectID, kind: link.kind,
      title: link.youtubeID.map { "YouTube · \($0)" } ?? link.url.host ?? "Webリンク", originalURL: link.url)
    guard storeProjectSource(source) else { return nil }
    if source.kind == .youtube { Task { await prepareProjectSource(source.id) } }
    return source.id
  }

  @discardableResult
  func storeProjectSource(_ source: ProjectSource) -> Bool {
    guard !isRestoring, source.projectID.map({ space(id: $0) != nil }) ?? true else { return false }
    var candidate = projectSources
    if let index = candidate.firstIndex(where: { $0.id == source.id }) { candidate[index] = source }
    else { candidate.insert(source, at: 0) }
    guard persistNow(candidate, forKey: StorageKey.projectSources) else { return false }
    projectSources = candidate
    invalidateProjectEvidence([.source(source.id)])
    return true
  }

  func addProjectNote(title: String, text: String, projectID: UUID) async throws -> UUID? {
    guard !isRestoring, space(id: projectID) != nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    guard text.utf8.count <= 512 * 1024 else { throw ProjectSourceFiles.Failure.noteTooLarge }
    let data = try JSONEncoder().encode([ProjectSourceText(text: text)])
    let name = try await ProjectSourceFiles.shared.write(data, extension: "json")
    var source = ProjectSource(projectID: projectID, kind: .note,
      title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(text.prefix(40)) : title)
    source.extractedTextReference = name
    source.processingStatus = .ready
    guard storeProjectSource(source) else {
      await ProjectSourceFiles.shared.remove([name]); return nil
    }
    return source.id
  }

  func updateProjectNote(_ id: UUID, title: String, text: String) async throws -> Bool {
    guard let previous = source(id: id), previous.kind == .note, !isRestoring,
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    guard text.utf8.count <= 512 * 1024 else { throw ProjectSourceFiles.Failure.noteTooLarge }
    let data = try JSONEncoder().encode([ProjectSourceText(text: text)])
    let name = try await ProjectSourceFiles.shared.write(data, extension: "json")
    guard var current = source(id: id), current.extractedTextReference == previous.extractedTextReference else {
      await ProjectSourceFiles.shared.remove([name]); return false
    }
    let old = current.extractedTextReference
    current.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(text.prefix(40)) : title
    current.extractedTextReference = name
    current.updatedAt = .now
    guard storeProjectSource(current) else { await ProjectSourceFiles.shared.remove([name]); return false }
    if let old { await ProjectSourceFiles.shared.remove([old]) }
    return true
  }

  func importProjectFile(_ url: URL, projectID: UUID) async throws -> UUID? {
    guard !isRestoring, space(id: projectID) != nil else { return nil }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    guard let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          bytes <= ProjectSourceFiles.maximumFileBytes else { throw ProjectSourceFiles.Failure.tooLarge }
    if ["m4a", "mp3", "wav", "aiff", "aif", "caf", "flac", "ogg"].contains(url.pathExtension.lowercased()) {
      guard !isImporting else { return nil }
      let existing = Set(meetings.map(\.id))
      await importAudio(from: url, spaceID: projectID)
      return meetings.first { !existing.contains($0.id) }?.id
    }
    let receipt = try await ProjectSourceFiles.shared.copy(url)
    return await addProjectFile(receipt: receipt, title: url.lastPathComponent, projectID: projectID)
  }

  func addProjectFile(receipt: ProjectSourceFiles.Receipt, title: String, projectID: UUID) async -> UUID? {
    guard !isRestoring, space(id: projectID) != nil else {
      await ProjectSourceFiles.shared.remove([receipt.reference]); return nil
    }
    if let existing = projectSources.first(where: { $0.projectID == projectID && $0.contentFingerprint == receipt.fingerprint }) {
      await ProjectSourceFiles.shared.remove([receipt.reference]); return existing.id
    }
    let suffix = (receipt.reference as NSString).pathExtension.lowercased()
    let kind: ProjectSource.Kind = suffix == "pdf" ? .pdf :
      ["jpg", "jpeg", "png", "heic", "heif", "tiff", "gif", "webp"].contains(suffix) ? .image : .document
    let source = ProjectSource(projectID: projectID, kind: kind, title: title,
      localFileReference: receipt.reference, contentFingerprint: receipt.fingerprint)
    guard storeProjectSource(source) else {
      await ProjectSourceFiles.shared.remove([receipt.reference]); return nil
    }
    await prepareProjectSource(source.id)
    return source.id
  }

  func prepareProjectSource(_ id: UUID) async {
    if let value = source(id: id), value.kind == .youtube {
      await prepareProjectYouTube(id)
      return
    }
    guard let source = source(id: id), source.processingStatus != .ready,
          !projectSourceProcessingIDs.contains(id), let name = source.localFileReference,
          let file = ProjectSourceFiles.resolve(name) else { return }
    projectSourceProcessingIDs.insert(id)
    defer { projectSourceProcessingIDs.remove(id) }
    var processing = source
    processing.processingStatus = .processing
    guard storeProjectSource(processing) else { return }
    var created: [String] = []
    do {
      let result = try await Task.detached(priority: .utility) { try ProjectSourceExtraction.read(file) }.value
      let text = result.blocks.isEmpty ? nil : try await ProjectSourceFiles.shared.write(JSONEncoder().encode(result.blocks), extension: "json")
      if let text { created.append(text) }
      var thumb: String?
      if let data = result.thumbnail { thumb = try await ProjectSourceFiles.shared.write(data, extension: "jpg") }
      if let thumb { created.append(thumb) }
      guard var current = self.source(id: id), current.localFileReference == name else {
        await ProjectSourceFiles.shared.remove(created); return
      }
      current.extractedTextReference = text
      current.thumbnailReference = thumb
      current.processingStatus = text == nil ? .unavailable : .ready
      current.errorInformation = result.notice
      if !storeProjectSource(current) { await ProjectSourceFiles.shared.remove(created) }
    } catch {
      await ProjectSourceFiles.shared.remove(created)
      guard var current = self.source(id: id), current.localFileReference == name else { return }
      current.processingStatus = .failed
      current.errorInformation = "解析できませんでした。元ファイルは保存されています。"
      _ = storeProjectSource(current)
    }
  }

  private func prepareProjectYouTube(_ id: UUID) async {
    guard var value = source(id: id), let url = value.originalURL,
          value.metadata?["youtubeTitle"] == nil || value.thumbnailReference == nil,
          !projectSourceProcessingIDs.contains(id) else { return }
    projectSourceProcessingIDs.insert(id)
    defer { projectSourceProcessingIDs.remove(id) }
    if value.metadata?["youtubeTitle"] == nil {
      value.processingStatus = .processing
      guard storeProjectSource(value) else { return }
      do {
        let metadata = try await ProjectYouTubeMetadata.fetch(url)
        guard var current = source(id: id), current.originalURL == url else { return }
        current.title = metadata.title
        current.metadata = ["youtubeTitle": metadata.title, "youtubeAuthor": metadata.author]
        current.processingStatus = .unavailable
        current.errorInformation = "動画情報を取得しました。字幕や動画内容は取得していないため、AIの根拠には使用しません。"
        guard storeProjectSource(current) else { return }
      } catch {
        guard var current = source(id: id), current.originalURL == url else { return }
        current.processingStatus = .unavailable
        current.errorInformation = "動画情報を取得できませんでした。リンクは保存されています。"
        _ = storeProjectSource(current)
        return
      }
    }
    guard source(id: id)?.thumbnailReference == nil else { return }
    var created: String?
    do {
      let data = try await ProjectYouTubeThumbnail.fetch(url)
      let jpeg = await Task.detached(priority: .utility) {
        ImageDownscale.downsampled(data: data, maxPixelSize: 160)?.jpegData(compressionQuality: 0.8)
      }.value
      guard let jpeg else { throw ProjectSourceFiles.Failure.invalidFile }
      let name = try await ProjectSourceFiles.shared.write(jpeg, extension: "jpg")
      created = name
      guard var current = source(id: id), current.originalURL == url, current.thumbnailReference == nil else {
        await ProjectSourceFiles.shared.remove([name]); return
      }
      current.thumbnailReference = name
      current.metadata?.removeValue(forKey: "thumbnailError")
      if !storeProjectSource(current) { await ProjectSourceFiles.shared.remove([name]) }
    } catch {
      if let created { await ProjectSourceFiles.shared.remove([created]) }
      guard !Task.isCancelled, var current = source(id: id), current.originalURL == url else { return }
      current.metadata?["thumbnailError"] = (error as? ProjectSourceFiles.Failure)?.errorDescription ??
        "サムネイルを取得できませんでした。動画リンクと情報は保存されています。"
      _ = storeProjectSource(current)
    }
  }

  @discardableResult
  func detachProjectSource(_ id: UUID) -> Bool {
    guard var source = source(id: id) else { return false }
    source.projectID = nil
    source.updatedAt = .now
    return storeProjectSource(source)
  }

  @discardableResult
  func deleteProjectSource(_ id: UUID) -> Bool {
    guard !isRestoring, let source = source(id: id) else { return false }
    let remaining = projectSources.filter { $0.id != id }
    guard persistNow(remaining, forKey: StorageKey.projectSources) else { return false }
    projectSources = remaining
    invalidateProjectEvidence([.source(id)])
    let retained = Set(remaining.flatMap(\.fileReferences))
    Task { await ProjectSourceFiles.shared.remove(source.fileReferences.filter { !retained.contains($0) }) }
    return true
  }
}
