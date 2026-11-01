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
    let link = try file.originalURL.map { try ProjectSourceURL.normalized($0.absoluteString) }
    if let link, let existing = projectSources.first(where: { $0.projectID == projectID && $0.originalURL == link.url }) {
      return existing.id
    }
    if file.url.pathExtension == "memorasource" {
      let data = try await SourceExtractionCache.shared.extract(file.url)
      guard context.isCurrent(in: self), let link else { return nil }
      if let existing = projectSources.first(where: { $0.projectID == projectID && $0.originalURL == link.url }) { return existing.id }
      guard !data.blocks.isEmpty else { throw ConversationSourceIntake.Failure.unavailable(data.notice ?? "参照できる本文がありません。") }
      let bytes = try JSONEncoder().encode(data.blocks)
      guard bytes.count <= ProjectSourceTextReader.maximumBytes else { throw ProjectSourceFiles.Failure.extractedTextTooLarge }
      let name = try await ProjectSourceFiles.shared.write(bytes, extension: "json")
      guard context.isCurrent(in: self) else { await ProjectSourceFiles.shared.remove([name]); return nil }
      if let existing = projectSources.first(where: { $0.projectID == projectID && $0.originalURL == link.url }) {
        await ProjectSourceFiles.shared.remove([name])
        guard context.isCurrent(in: self), source(id: existing.id)?.hasSameReadableEvidence(as: existing) == true else { return nil }
        return existing.id
      }
      var source = ProjectSource(projectID: projectID, kind: link.kind, title: file.name, originalURL: link.url,
        extractedTextReference: name, processingStatus: .ready, textCoverage: .partial)
      source.acquiredAt = .now
      source.errorInformation = data.notice
      guard storeProjectSource(source) else { await ProjectSourceFiles.shared.remove([name]); return nil }
      scheduleProjectSourcePreparation(source.id)
      return context.isCurrent(in: self) ? source.id : nil
    }
    return try await importProjectFile(file.url, projectID: projectID, importContext: context,
      waitsForPreparation: false, sourceTitle: file.name, originalURL: link?.url)
  }
}
