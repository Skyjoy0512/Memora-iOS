import CryptoKit
import Foundation

extension MemoraModel {
  /// Stores one captured thing in the given destination.
  ///
  /// The destination is a LocalImportContext, so a capture cannot land in a
  /// workspace that changed while it was being prepared.
  ///
  /// A URL or text that is already stored in the same destination is not
  /// stored twice: the existing source is returned as `.duplicate`. A file
  /// or an image is deduplicated by its content fingerprint.
  ///
  /// `sourceID` keeps an identity chosen by the caller, such as a retried
  /// share item, and `metadata` travels with the source. The coordinator
  /// writes its own fingerprint and meeting marker after the caller's values,
  /// so those markers cannot be replaced. `title` is the name the caller
  /// already knows the item by; without one the coordinator names it.
  /// `removing` holds the draft keys that must be settled in the same
  /// transaction as the record, so a saved capture never leaves a draft that
  /// restores as a duplicate.
  ///
  /// `.audio` is stored as a record that is transcribed, not as a source.
  /// `.meeting` is stored as a link source that carries the meeting marker in
  /// its metadata.
  func capture(_ intent: CaptureIntent, context: LocalImportContext, sourceID: UUID? = nil,
               metadata: [String: String] = [:], title: String? = nil,
               removing: [String] = []) async -> CaptureOutcome {
    guard !isRestoring, !isStoreProtected, currentTeamID == nil else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    guard context.isCurrent(in: self) else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }

    switch intent {
    case .url(let url):
      return await captureLink(url, context: context, isMeeting: false, sourceID: sourceID, metadata: metadata, title: title, removing: removing)
    case .meeting(let url):
      return await captureLink(url, context: context, isMeeting: true, sourceID: sourceID, metadata: metadata, title: title, removing: removing)
    case .text(let text):
      return await captureText(text, context: context, sourceID: sourceID, metadata: metadata, title: title, removing: removing)
    case .image(let data):
      return await captureImage(data, context: context, sourceID: sourceID, metadata: metadata, title: title, removing: removing)
    case .file(let url):
      return await captureFile(url, context: context, sourceID: sourceID, metadata: metadata, title: title, removing: removing)
    case .audio(let url):
      return await captureAudio(url, context: context, sourceID: sourceID, metadata: metadata)
    }
  }

  /// Stores a source that a caller has already prepared.
  ///
  /// The context is the destination: a stale destination or a store that may
  /// not be written refuses the capture, so prepared work cannot land in a
  /// workspace that changed while it was being built. A source is deduplicated
  /// only inside the context's project, by a non-nil content fingerprint, a
  /// non-nil original URL, or all four PDF partition values. A matched source
  /// reuses the saved record and preserves its evidence. `removing` holds
  /// the draft keys settled in the same transaction as the record.
  func capture(_ source: ProjectSource, context: LocalImportContext,
               removing: [String] = []) -> CaptureOutcome {
    guard !isRestoring, !isStoreProtected, currentTeamID == nil else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    guard context.isCurrent(in: self) else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    guard source.projectID == context.projectID else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    if let existing = duplicateCapture(of: source) {
      return reuseCapture(existing.id, removing: removing)
    }
    // A caller-supplied ID must not replace previously stored evidence.
    guard self.source(id: source.id) == nil else {
      return .refused("同じ識別子の資料が既に保存されています。")
    }
    guard storeProjectSource(source, removing: removing) else {
      return .refused("資料を保存できませんでした。ストレージの空き容量を確認してください。")
    }
    guard context.isCurrent(in: self) else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    scheduleProjectSourcePreparation(source.id)
    return .imported(source.id)
  }

  private func duplicateCapture(of source: ProjectSource) -> ProjectSource? {
    let textFingerprint = source.kind == .note ? source.metadata?["captureFingerprint"] : nil
    let partitionKeys = ["partitionOriginalFingerprint", "partitionOriginalPageCount",
      "partitionFirstPage", "partitionLastPage"]
    return projectSources.first { candidate in
      guard candidate.projectID == source.projectID else { return false }
      let sameFingerprint = source.contentFingerprint != nil && candidate.contentFingerprint == source.contentFingerprint
      let sameText = textFingerprint != nil && candidate.kind == .note && candidate.metadata?["captureFingerprint"] == textFingerprint
      let sameOriginalURL = source.originalURL != nil && candidate.originalURL == source.originalURL
      let samePartition = partitionKeys.allSatisfy { key in
        guard let value = source.metadata?[key] else { return false }
        return candidate.metadata?[key] == value
      }
      return sameFingerprint || sameText || sameOriginalURL || samePartition
    }
  }

  private func reuseCapture(_ id: UUID, removing: [String]) -> CaptureOutcome {
    guard removing.isEmpty || persistBatch({ [] }, removing: removing) else {
      return .refused("保存できませんでした。ストレージの空き容量を確認してください。")
    }
    return .duplicate(id)
  }

  /// A public link, and a meeting that is kept as a link with a marker.
  private func captureLink(_ url: URL, context: LocalImportContext, isMeeting: Bool,
                           sourceID: UUID?, metadata: [String: String], title: String?,
                           removing: [String]) async -> CaptureOutcome {
    let link: ProjectSourceURL.Link
    do {
      link = try ProjectSourceURL.normalized(url.absoluteString)
    } catch {
      return .refused("公開されたHTTPSリンクを保存できません。")
    }
    guard context.isCurrent(in: self) else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    if let existing = projectSources.first(where: {
      $0.projectID == context.projectID && $0.originalURL == link.url
    }) {
      if !removing.isEmpty, !persistBatch({ [] }, removing: removing) {
        return .refused("保存できませんでした。ストレージの空き容量を確認してください。")
      }
      return .duplicate(existing.id)
    }
    let resolvedTitle: String
    var mergedMetadata = metadata
    if isMeeting {
      resolvedTitle = link.url.host ?? "会議"
      mergedMetadata["captureKind"] = "meeting"
    } else {
      resolvedTitle = link.youtubeID.map { "YouTube · \($0)" } ?? link.url.host ?? "Webリンク"
    }
    let name = title.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? resolvedTitle
    var source = ProjectSource(projectID: context.projectID, kind: link.kind, title: name,
      originalURL: link.url, metadata: mergedMetadata.isEmpty ? nil : mergedMetadata)
    if let sourceID { source.id = sourceID }
    guard context.isCurrent(in: self) else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    guard storeProjectSource(source, removing: removing) else {
      return .refused("リンクを保存できませんでした。ストレージの空き容量を確認してください。")
    }
    guard context.isCurrent(in: self) else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    scheduleProjectSourcePreparation(source.id)
    return .imported(source.id)
  }

  /// Copied text, stored as a note that is never longer than the limit.
  private func captureText(_ text: String, context: LocalImportContext,
                           sourceID: UUID?, metadata: [String: String], title: String?,
                           removing: [String]) async -> CaptureOutcome {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .refused("保存するテキストを入力してください。") }
    guard text.count <= 10_000 else {
      return .refused("テキストが長すぎます。10,000文字以内で入力してください。")
    }
    let fingerprint = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    var mergedMetadata = metadata
    mergedMetadata["captureFingerprint"] = fingerprint
    guard context.isCurrent(in: self) else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    var source = ProjectSource(projectID: context.projectID, kind: .note,
      title: title.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? String(text.prefix(40)), metadata: mergedMetadata)
    if let sourceID { source.id = sourceID }
    if let existing = duplicateCapture(of: source) {
      return reuseCapture(existing.id, removing: removing)
    }
    let data: Data
    do {
      data = try JSONEncoder().encode([ProjectSourceText(text: text)])
    } catch {
      return .refused("テキストを保存できませんでした。ストレージの空き容量を確認してください。")
    }
    let name: String
    do {
      name = try await ProjectSourceFiles.shared.write(data, extension: "json")
    } catch {
      return .refused("テキストを保存できませんでした。ストレージの空き容量を確認してください。")
    }
    source.extractedTextReference = name
    source.processingStatus = .ready
    source.textCoverage = .complete
    source.acquiredAt = .now
    return await registerStagedCapture(source, reference: name, context: context, removing: removing)
  }

  /// A picture, stored through the existing import path so the fingerprint
  /// deduplication stays in one place. A caller's identity is stored directly
  /// so a retried share keeps the same source.
  private func captureImage(_ data: Data, context: LocalImportContext,
                            sourceID: UUID?, metadata: [String: String], title: String?,
                            removing: [String]) async -> CaptureOutcome {
    guard !data.isEmpty, data.count <= ProjectSourceFiles.maximumFileBytes else {
      return .refused("写真が大きすぎます。")
    }
    let fingerprint = await Task.detached(priority: .utility) {
      SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }.value
    guard context.isCurrent(in: self) else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    var source = ProjectSource(projectID: context.projectID, kind: .image,
      title: title.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? "写真",
      contentFingerprint: fingerprint, metadata: metadata.isEmpty ? nil : metadata)
    if let sourceID { source.id = sourceID }
    if let existing = duplicateCapture(of: source) {
      return reuseCapture(existing.id, removing: removing)
    }
    do {
      let reference = try await ProjectSourceFiles.shared.write(data, extension: "jpg")
      source.localFileReference = reference
      return await registerStagedCapture(source, reference: reference, context: context, removing: removing)
    } catch {
      return .refused("写真を保存できませんでした。ストレージの空き容量を確認してください。")
    }
  }

  private func registerStagedCapture(_ source: ProjectSource, reference: String,
                                     context: LocalImportContext, removing: [String]) async -> CaptureOutcome {
    // Another capture can finish while disk I/O suspends the caller. Check
    // for a duplicate again in the same actor turn as SQLite registration.
    let outcome = capture(source, context: context, removing: removing)
    if case .imported = outcome { return outcome }
    await ProjectSourceFiles.shared.remove([reference])
    return outcome
  }

  /// A file, copied into managed storage and deduplicated by its destination
  /// and content fingerprint.
  private func captureFile(_ url: URL, context: LocalImportContext,
                           sourceID: UUID?, metadata: [String: String], title: String?,
                           removing: [String]) async -> CaptureOutcome {
    let receipt: ProjectSourceFiles.Receipt
    do {
      receipt = try await ProjectSourceFiles.shared.copy(url)
    } catch {
      return .refused("ファイルを保存できませんでした。ストレージの空き容量を確認してください。")
    }
    guard context.isCurrent(in: self) else {
      await ProjectSourceFiles.shared.remove([receipt.reference])
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    if let existing = projectSources.first(where: {
      $0.projectID == context.projectID && $0.contentFingerprint == receipt.fingerprint
    }) {
      await ProjectSourceFiles.shared.remove([receipt.reference])
      if !removing.isEmpty, !persistBatch({ [] }, removing: removing) {
        return .refused("保存できませんでした。ストレージの空き容量を確認してください。")
      }
      return .duplicate(existing.id)
    }
    var source = ProjectSource(projectID: context.projectID, kind: SourceIntake.kind(for: url),
      title: title.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? url.lastPathComponent,
      localFileReference: receipt.reference,
      contentFingerprint: receipt.fingerprint, metadata: metadata.isEmpty ? nil : metadata)
    if let sourceID { source.id = sourceID }
    guard storeProjectSource(source, removing: removing) else {
      await ProjectSourceFiles.shared.remove([receipt.reference])
      return .refused("ファイルを保存できませんでした。ストレージの空き容量を確認してください。")
    }
    guard context.isCurrent(in: self) else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    scheduleProjectSourcePreparation(source.id)
    return .imported(source.id)
  }

  /// An audio file, stored as a record that is transcribed. A share identity
  /// and metadata belong to sources, so audio accepts and ignores both.
  private func captureAudio(_ url: URL, context: LocalImportContext,
                            sourceID: UUID?, metadata: [String: String]) async -> CaptureOutcome {
    let id = await importAudio(from: url, spaceID: context.projectID, importContext: context)
    guard context.isCurrent(in: self) else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    guard let id else {
      return .refused("音声を取り込めませんでした。再生できるファイルをお試しください。")
    }
    return .imported(id)
  }
}
