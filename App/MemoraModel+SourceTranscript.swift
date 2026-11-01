import Foundation

extension MemoraModel {
  func importSourceTranscript(_ text: String, source expected: ProjectSource,
    context: LocalImportContext?, captionReference: String? = nil,
    notice: String = "利用者が提供した字幕・文字起こしです。動画の全文との一致は未確認です。"
  ) async throws -> UUID? {
    guard let context, context.isCurrent(in: self), source(id: expected.id) == expected,
          !projectSourceProcessingIDs.contains(expected.id) else { return nil }
    let blocks = SubtitleText.blocks(text)
    guard !blocks.isEmpty else { return nil }
    let data = try JSONEncoder().encode(blocks)
    guard data.count <= ProjectSourceTextReader.maximumBytes else { throw ProjectSourceFiles.Failure.extractedTextTooLarge }
    let name = try await ProjectSourceFiles.shared.write(data, extension: "json")
    guard context.isCurrent(in: self), source(id: expected.id) == expected else {
      await ProjectSourceFiles.shared.remove([name]); return nil
    }
    var source = expected
    source.retainRevision()
    source.extractedTextReference = name
    source.captionFileReference = captionReference ?? expected.captionFileReference
    source.processingStatus = .ready
    source.textCoverage = .partial
    source.acquiredAt = .now
    source.updatedAt = .now
    source.summaryStatus = nil
    source.errorInformation = notice
    guard storeProjectSource(source) else { await ProjectSourceFiles.shared.remove([name]); return nil }
    let retained = Set(projectSources.flatMap(\.fileReferences))
    await ProjectSourceFiles.shared.remove(expected.fileReferences.filter { !retained.contains($0) })
    await summarizeProjectSource(source.id)
    return context.isCurrent(in: self) ? source.id : nil
  }

  func importSourceTranscriptFile(_ url: URL, source expected: ProjectSource, context: LocalImportContext?) async throws -> UUID? {
    guard let context, context.isCurrent(in: self), source(id: expected.id) == expected else { return nil }
    let receipt = try await ProjectSourceFiles.shared.copy(url)
    var retained = false
    defer {
      if !retained { Task { await ProjectSourceFiles.shared.remove([receipt.reference]) } }
    }
    guard context.isCurrent(in: self), source(id: expected.id) == expected,
          let file = ProjectSourceFiles.resolve(receipt.reference) else { return nil }
    switch SourceIntake.kind(for: file) {
    case .audio, .video:
      var source = expected
      source.retainRevision()
      source.localFileReference = receipt.reference
      source.contentFingerprint = receipt.fingerprint
      source.processingStatus = .pending
      source.updatedAt = .now
      guard storeProjectSource(source) else { return nil }
      retained = true
      await prepareProjectSource(source.id)
      return context.isCurrent(in: self) ? source.id : nil
    default:
      guard ["srt", "vtt", "txt", "text"].contains(file.pathExtension.lowercased()) else { throw ProjectSourceFiles.Failure.invalidFile }
      let data = try await Task.detached(priority: .utility) { try BoundedTextReader.read(file, maximumBytes: 4 * 1024 * 1024) }.value
      guard !data.wasTruncated else { throw ProjectSourceFiles.Failure.extractedTextTooLarge }
      let id = try await importSourceTranscript(data.text, source: expected, context: context, captionReference: receipt.reference)
      retained = id != nil
      return id
    }
  }

  func prepareLegacySourceTranscript(_ id: UUID) async {
    guard let source = source(id: id), !source.canProvideText,
          let recordID = source.metadata?["videoTranscriptMeetingID"].flatMap(UUID.init(uuidString:)),
          let record = meeting(id: recordID), record.spaceID == source.projectID, record.privacy == source.privacy,
          !record.transcript.isEmpty, let context = LocalImportContext(projectID: source.projectID, in: self) else { return }
    let blocks = record.transcript.flatMap { SourceTextChunks.split($0.text, time: record.duration > 0 ? $0.timestamp : nil) }
    guard let data = try? JSONEncoder().encode(blocks), data.count <= ProjectSourceTextReader.maximumBytes,
          let name = try? await ProjectSourceFiles.shared.write(data, extension: "json") else { return }
    guard context.isCurrent(in: self), self.source(id: id) == source, meeting(id: recordID) == record else {
      await ProjectSourceFiles.shared.remove([name]); return
    }
    var current = source
    current.extractedTextReference = name
    current.processingStatus = .ready
    current.textCoverage = .partial
    if record.status == .ready, !record.summary.isEmpty {
      current.summary = record.summary
      current.summaryStatus = .ready
      current.summaryTextReference = name
    }
    if !storeProjectSource(current) { await ProjectSourceFiles.shared.remove([name]) }
  }
}
