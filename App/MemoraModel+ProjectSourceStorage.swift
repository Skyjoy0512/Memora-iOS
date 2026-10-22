import Foundation

extension MemoraModel {
  func source(id: UUID) -> ProjectSource? { projectSourceIndex.element(id, in: projectSources) }

  @discardableResult
  func storeProjectSource(_ source: ProjectSource, presentsErrorsLocally: Bool = false) -> Bool {
    if presentsErrorsLocally {
      return handlingPersistenceFailureLocally { commitProjectSource(source) }
    }
    return commitProjectSource(source)
  }

  private func commitProjectSource(_ source: ProjectSource) -> Bool {
    // Team storage is not connected. Never write its apparent records into the
    // personal SQLite document, including after an asynchronous import returns.
    guard !isRestoring, currentTeamID == nil, isStoreWritable(),
          source.projectID.map({ space(id: $0) != nil }) ?? true else { return false }
    var candidate = projectSources
    if let index = candidate.firstIndex(where: { $0.id == source.id }) { candidate[index] = source }
    else { candidate.insert(source, at: 0) }
    guard persistNow(candidate, forKey: StorageKey.projectSources) else { return false }
    projectSources = candidate
    invalidateProjectEvidence([.source(source.id)])
    return true
  }

  func addProjectNote(title: String, text: String, projectID: UUID, presentsErrorsLocally: Bool = false) async throws -> UUID? {
    guard !Task.isCancelled, !isRestoring, !isStoreProtected, currentTeamID == nil,
          let project = space(id: projectID), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    let data = try Self.encodedProjectNote(text)
    let generation = aiWorkspaceGeneration
    let name = try await ProjectSourceFiles.shared.write(data, extension: "json")
    guard !Task.isCancelled, !isRestoring, !isStoreProtected, currentTeamID == nil,
          aiWorkspaceGeneration == generation, space(id: projectID) == project else {
      await ProjectSourceFiles.shared.remove([name]); return nil
    }
    var source = ProjectSource(projectID: projectID, kind: .note,
      title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(text.prefix(40)) : title)
    source.extractedTextReference = name
    source.processingStatus = .ready
    source.textCoverage = .complete
    guard storeProjectSource(source, presentsErrorsLocally: presentsErrorsLocally) else {
      await ProjectSourceFiles.shared.remove([name]); return nil
    }
    return source.id
  }

  func updateProjectNote(_ id: UUID, title: String, text: String, presentsErrorsLocally: Bool = false) async throws -> Bool {
    guard !Task.isCancelled, !isRestoring, !isStoreProtected, currentTeamID == nil,
          let previous = source(id: id), previous.kind == .note,
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    let project = previous.projectID.flatMap { space(id: $0) }
    guard previous.projectID == nil || project != nil else { return false }
    let data = try Self.encodedProjectNote(text)
    let generation = aiWorkspaceGeneration
    let name = try await ProjectSourceFiles.shared.write(data, extension: "json")
    // A matching file name alone misses privacy changes, moves, renames and
    // replacement records. A → B → A workspace switches also invalidate work.
    guard !Task.isCancelled, !isRestoring, !isStoreProtected, currentTeamID == nil,
          aiWorkspaceGeneration == generation, source(id: id) == previous,
          previous.projectID.flatMap({ space(id: $0) }) == project else {
      await ProjectSourceFiles.shared.remove([name]); return false
    }
    var current = previous
    current.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(text.prefix(40)) : title
    current.extractedTextReference = name
    current.processingStatus = .ready
    current.textCoverage = .complete
    current.errorInformation = nil
    current.updatedAt = .now
    guard storeProjectSource(current, presentsErrorsLocally: presentsErrorsLocally) else {
      await ProjectSourceFiles.shared.remove([name]); return false
    }
    if let old = previous.extractedTextReference, !projectSources.contains(where: { $0.fileReferences.contains(old) }) {
      await ProjectSourceFiles.shared.remove([old])
    }
    return true
  }

  private static func encodedProjectNote(_ text: String) throws -> Data {
    guard text.utf8.count <= 512 * 1024 else { throw ProjectSourceFiles.Failure.noteTooLarge }
    let data = try JSONEncoder().encode([ProjectSourceText(text: text)])
    // JSON escaping can exceed the reader's limit even when the raw text fits.
    guard data.count <= ProjectSourceTextReader.maximumBytes else { throw ProjectSourceFiles.Failure.noteEncodingTooLarge }
    return data
  }
}
