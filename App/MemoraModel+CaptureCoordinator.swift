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
  /// or an image is deduplicated by its content fingerprint, which the
  /// existing import helpers already do.
  ///
  /// `.audio` is stored as a record that is transcribed, not as a source.
  /// `.meeting` is stored as a link source that carries the meeting marker in
  /// its metadata.
  func capture(_ intent: CaptureIntent, context: LocalImportContext) async -> CaptureOutcome {
    guard !isRestoring, !isStoreProtected, currentTeamID == nil else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    guard context.isCurrent(in: self) else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }

    switch intent {
    case .url(let url):
      return await captureLink(url, context: context, isMeeting: false)
    case .meeting(let url):
      return await captureLink(url, context: context, isMeeting: true)
    case .text(let text):
      return await captureText(text, context: context)
    case .image(let data):
      return await captureImage(data, context: context)
    case .file(let url):
      return await captureFile(url, context: context)
    case .audio(let url):
      return await captureAudio(url, context: context)
    }
  }

  /// A public link, and a meeting that is kept as a link with a marker.
  private func captureLink(_ url: URL, context: LocalImportContext, isMeeting: Bool) async -> CaptureOutcome {
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
      return .duplicate(existing.id)
    }
    let title: String
    let metadata: [String: String]
    if isMeeting {
      title = link.url.host ?? "会議"
      metadata = ["captureKind": "meeting"]
    } else {
      title = link.youtubeID.map { "YouTube · \($0)" } ?? link.url.host ?? "Webリンク"
      metadata = [:]
    }
    let source = ProjectSource(projectID: context.projectID, kind: link.kind, title: title,
      originalURL: link.url, metadata: metadata.isEmpty ? nil : metadata)
    guard context.isCurrent(in: self) else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    guard storeProjectSource(source) else {
      return .refused("リンクを保存できませんでした。ストレージの空き容量を確認してください。")
    }
    guard context.isCurrent(in: self) else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    scheduleProjectSourcePreparation(source.id)
    return .imported(source.id)
  }

  /// Copied text, stored as a note that is never longer than the limit.
  private func captureText(_ text: String, context: LocalImportContext) async -> CaptureOutcome {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return .refused("テキストが長すぎます。10,000文字以内で入力してください。")
    }
    guard text.count <= 10_000 else {
      return .refused("テキストが長すぎます。10,000文字以内で入力してください。")
    }
    let fingerprint = SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    guard context.isCurrent(in: self) else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    if let existing = projectSources.first(where: {
      $0.projectID == context.projectID && $0.metadata?["captureFingerprint"] == fingerprint
    }) {
      return .duplicate(existing.id)
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
    guard context.isCurrent(in: self) else {
      await ProjectSourceFiles.shared.remove([name])
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    var source = ProjectSource(projectID: context.projectID, kind: .note,
      title: String(text.prefix(40)), metadata: ["captureFingerprint": fingerprint])
    source.extractedTextReference = name
    source.processingStatus = .ready
    source.textCoverage = .complete
    source.acquiredAt = .now
    guard storeProjectSource(source) else {
      await ProjectSourceFiles.shared.remove([name])
      return .refused("テキストを保存できませんでした。ストレージの空き容量を確認してください。")
    }
    guard context.isCurrent(in: self) else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    scheduleProjectSourcePreparation(source.id)
    return .imported(source.id)
  }

  /// A picture, stored through the existing import path so the fingerprint
  /// deduplication stays in one place.
  private func captureImage(_ data: Data, context: LocalImportContext) async -> CaptureOutcome {
    guard !data.isEmpty, data.count <= ProjectSourceFiles.maximumFileBytes else {
      return .refused("写真が大きすぎます。")
    }
    let fingerprint = await Task.detached(priority: .utility) {
      SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }.value
    guard context.isCurrent(in: self) else {
      return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
    }
    if let existing = projectSources.first(where: {
      $0.projectID == context.projectID && $0.contentFingerprint == fingerprint
    }) {
      return .duplicate(existing.id)
    }
    do {
      let id = try await importProjectSource(title: "写真", context: context,
        presentsErrorsLocally: true, waitsForPreparation: false) {
        let reference = try await ProjectSourceFiles.shared.write(data, extension: "jpg")
        return ProjectSourceFiles.Receipt(reference: reference, fingerprint: fingerprint)
      }
      guard context.isCurrent(in: self) else {
        return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
      }
      guard let id else {
        return .refused("写真を保存できませんでした。ストレージの空き容量を確認してください。")
      }
      return .imported(id)
    } catch {
      return .refused("写真を保存できませんでした。ストレージの空き容量を確認してください。")
    }
  }

  /// A file, stored through the existing import path.
  private func captureFile(_ url: URL, context: LocalImportContext) async -> CaptureOutcome {
    do {
      let id = try await importProjectFile(url, projectID: context.projectID,
        importContext: context, presentsErrorsLocally: true)
      guard context.isCurrent(in: self) else {
        return .refused("保存先が変更されたため取り込めませんでした。画面を開き直してください。")
      }
      guard let id else {
        return .refused("ファイルを保存できませんでした。ストレージの空き容量を確認してください。")
      }
      return .imported(id)
    } catch {
      return .refused("ファイルを保存できませんでした。ストレージの空き容量を確認してください。")
    }
  }

  /// An audio file, stored as a record that is transcribed.
  private func captureAudio(_ url: URL, context: LocalImportContext) async -> CaptureOutcome {
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
