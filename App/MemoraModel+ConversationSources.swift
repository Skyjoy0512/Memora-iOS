import Foundation

extension MemoraModel {
  func conversationAttachment(adding explicit: AIAttachment?) -> AIAttachment? {
    let candidates = (explicit?.files ?? []) + aiMessages.reversed().filter { $0.role == .user }.flatMap { $0.attachment?.files ?? [] }
    var seen: Set<UUID> = []
    let files = Array(candidates.filter { seen.insert($0.id).inserted }.prefix(10))
    guard let first = files.first else { return nil }
    return AIAttachment(id: first.id, name: first.name, url: first.url,
      additionalFiles: files.count > 1 ? Array(files.dropFirst()) : nil, originalURL: first.originalURL, sourceMetadata: first.sourceMetadata)
  }

  /// Prepares one capture intent into a readable attachment.
  ///
  /// A link is fetched into the snapshot the conversation reads. The
  /// attachment keeps the link so a citation points at the source.
  func prepareConversationSource(_ intent: CaptureIntent) async throws -> AIAttachment {
    switch intent {
    case .url(let url):
      return try await ConversationSourceIntake.prepare(url)
    case .text(let text):
      let reference: String
      do {
        reference = try await AIAttachmentFiles.shared.write(Data(text.utf8), extension: "txt")
      } catch {
        throw ConversationSourceIntake.Failure.unavailable("添付を保存できませんでした。")
      }
      let file = try AIAttachmentFiles.url(reference)
      return AIAttachment(id: UUID(), name: String(text.prefix(40)), url: file)
    case .image(let data):
      let reference = try await AIAttachmentFiles.shared.write(data, extension: "jpg")
      let file = try AIAttachmentFiles.url(reference)
      return AIAttachment(id: UUID(), name: "写真", url: file)
    case .file, .audio, .meeting:
      throw ConversationSourceIntake.Failure.unavailable("この添付は準備できません。")
    }
  }

  func prepareConversationSources(question: String, attachment: AIAttachment?, includesHistory: Bool) async throws -> AIAttachment? {
    guard let context = LocalImportContext(in: self) else { throw ConversationSourceIntake.Failure.unavailable("保存先を確認してください。") }
    var combined = includesHistory ? conversationAttachment(adding: attachment) : attachment
    var created: [URL] = []
    do {
      for url in InlineURLDetector.urls(in: question) {
        if combined?.files.contains(where: { $0.originalURL == url }) == true { continue }
        guard (combined?.files.count ?? 0) < 10 else { throw ConversationSourceIntake.Failure.unavailable("一度に参照できる添付は10件です。新しい会話でリンクを送信してください。") }
        let intent = ConversationSourceIntake.intent(forLink: url)
        let file = try await prepareConversationSource(intent)
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
    guard AIAttachment.isValidSourceMetadata(file.sourceMetadata) else { throw ProjectSourceFiles.Failure.invalidFile }
    guard let context = LocalImportContext(projectID: projectID, in: self) else { return nil }
    let link = try file.originalURL.map { try ProjectSourceURL.normalized($0.absoluteString) }
    if let link, let existing = projectSources.first(where: { $0.projectID == projectID && $0.originalURL == link.url }) {
      return existing.id
    }
    if file.url.pathExtension == "memorasource" {
      let data = try await SourceExtractionCache.shared.extract(file.url)
      guard context.isCurrent(in: self), let link else { return nil }
      if let existing = projectSources.first(where: { $0.projectID == projectID && $0.originalURL == link.url }) {
        guard source(id: existing.id)?.hasSameReadableEvidence(as: existing) == true else { return nil }
        return existing.id
      }
      guard !data.blocks.isEmpty else { throw ConversationSourceIntake.Failure.unavailable(data.notice ?? "参照できる本文がありません。") }
      let bytes = try JSONEncoder().encode(data.blocks)
      guard bytes.count <= ProjectSourceTextReader.maximumBytes else { throw ProjectSourceFiles.Failure.extractedTextTooLarge }
      let name = try await ProjectSourceFiles.shared.write(bytes, extension: "json")
      guard context.isCurrent(in: self) else { await ProjectSourceFiles.shared.remove([name]); return nil }
      // Another writer may have stored the same link while the text was
      // extracted. The stored record is the one that holds this content.
      if let existing = projectSources.first(where: { $0.projectID == projectID && $0.originalURL == link.url }) {
        await ProjectSourceFiles.shared.remove([name])
        guard context.isCurrent(in: self), source(id: existing.id)?.hasSameReadableEvidence(as: existing) == true else { return nil }
        return existing.id
      }
      var source = ProjectSource(projectID: projectID, kind: link.kind, title: file.name, originalURL: link.url,
        extractedTextReference: name, processingStatus: .ready, textCoverage: .partial)
      source.acquiredAt = .now
      source.errorInformation = data.notice
      switch capture(source, context: context) {
      case .imported(let id):
        guard context.isCurrent(in: self) else { return nil }
        return id
      case .duplicate(let id):
        await ProjectSourceFiles.shared.remove([name])
        guard context.isCurrent(in: self) else { return nil }
        return id
      case .refused:
        await ProjectSourceFiles.shared.remove([name])
        return nil
      }
    }
    return try await importProjectFile(file.url, projectID: projectID, importContext: context,
      waitsForPreparation: false, sourceTitle: file.name, originalURL: link?.url, sourceMetadata: file.sourceMetadata)
  }
}
