import Foundation

extension MemoraModel {
  func conversationAttachment(adding explicit: AIAttachment?) -> AIAttachment? {
    let candidates = (explicit?.files ?? []) + aiMessages.reversed().filter { $0.role == .user }.flatMap { $0.attachment?.files ?? [] }
    var seen: Set<UUID> = []
    let files = Array(candidates.filter { seen.insert($0.id).inserted }.prefix(10))
    guard let first = files.first else { return nil }
    return AIAttachment(id: first.id, name: first.name, url: first.url,
      additionalFiles: files.count > 1 ? Array(files.dropFirst()) : nil, originalURL: first.originalURL)
  }

  func prepareConversationSources(question: String, attachment: AIAttachment?, includesHistory: Bool) async throws -> AIAttachment? {
    guard let context = LocalImportContext(in: self) else { throw ConversationSourceIntake.Failure.unavailable("保存先を確認してください。") }
    var combined = includesHistory ? conversationAttachment(adding: attachment) : attachment
    var created: [URL] = []
    do {
      for url in InlineURLDetector.urls(in: question) {
        if combined?.files.contains(where: { $0.originalURL == url }) == true { continue }
        guard (combined?.files.count ?? 0) < 10 else { throw ConversationSourceIntake.Failure.unavailable("一度に参照できる添付は10件です。新しい会話でリンクを送信してください。") }
        let file = try await ConversationSourceIntake.prepare(url)
        created.append(file.url)
        guard context.isCurrent(in: self) else { throw CancellationError() }
        if combined == nil { combined = file } else { combined?.append(file) }
      }
      guard context.isCurrent(in: self) else { throw CancellationError() }
      return combined
    } catch {
      for url in created { try? FileManager.default.removeItem(at: url) }
      throw error
    }
  }

  func saveConversationFile(_ file: AIAttachment.File, projectID: UUID? = nil) async throws -> UUID? {
    guard let context = LocalImportContext(projectID: projectID, in: self) else { return nil }
    if file.url.pathExtension == "memorasource" {
      let data = try await AttachmentExtractionCache.shared.extract(file.url)
      guard context.isCurrent(in: self), let url = file.originalURL else { return nil }
      let link = try ProjectSourceURL.normalized(url.absoluteString)
      if let existing = projectSources.first(where: { $0.projectID == projectID && $0.originalURL == link.url }) { return existing.id }
      let bytes = try JSONEncoder().encode(data.blocks)
      guard bytes.count <= ProjectSourceTextReader.maximumBytes else { throw ProjectSourceFiles.Failure.extractedTextTooLarge }
      let name = try await ProjectSourceFiles.shared.write(bytes, extension: "json")
      guard context.isCurrent(in: self) else { await ProjectSourceFiles.shared.remove([name]); return nil }
      var source = ProjectSource(projectID: projectID, kind: link.kind, title: file.name, originalURL: link.url,
        extractedTextReference: name, processingStatus: .ready, textCoverage: .partial)
      source.acquiredAt = .now
      source.errorInformation = data.notice
      guard storeProjectSource(source) else { await ProjectSourceFiles.shared.remove([name]); return nil }
      await summarizeProjectSource(source.id)
      return context.isCurrent(in: self) ? source.id : nil
    }
    let id = try await importProjectFile(file.url, projectID: projectID, importContext: context)
    if let id, var source = source(id: id), let url = file.originalURL, context.isCurrent(in: self) {
      source.originalURL = try ProjectSourceURL.normalized(url.absoluteString).url
      _ = storeProjectSource(source)
    }
    return id
  }
}
