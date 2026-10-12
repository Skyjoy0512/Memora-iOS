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
    return storeProjectSource(source) ? source.id : nil
  }

  @discardableResult
  func storeProjectSource(_ source: ProjectSource) -> Bool {
    guard !isRestoring, source.projectID.map({ space(id: $0) != nil }) ?? true else { return false }
    var candidate = projectSources
    if let index = candidate.firstIndex(where: { $0.id == source.id }) { candidate[index] = source }
    else { candidate.insert(source, at: 0) }
    guard persistNow(candidate, forKey: StorageKey.projectSources) else { return false }
    projectSources = candidate
    return true
  }

  func addProjectNote(title: String, text: String, projectID: UUID) async throws -> UUID? {
    guard !isRestoring, space(id: projectID) != nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
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

  func importProjectFile(_ url: URL, projectID: UUID) async throws -> UUID? {
    guard !isRestoring, space(id: projectID) != nil else { return nil }
    if ["m4a", "mp3", "wav", "aiff", "aif", "caf", "flac", "ogg"].contains(url.pathExtension.lowercased()) {
      await importAudio(from: url, spaceID: projectID)
      return nil
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
    return source.id
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
    let retained = Set(remaining.flatMap(\.fileReferences))
    Task { await ProjectSourceFiles.shared.remove(source.fileReferences.filter { !retained.contains($0) }) }
    return true
  }
}
