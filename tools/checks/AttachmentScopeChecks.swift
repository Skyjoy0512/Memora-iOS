import Foundation

@main
struct AttachmentScopeChecks {
  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("AttachmentScopeChecks-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appendingPathComponent("note.txt")
    let data = Data("A日本語😀Z".utf8)
    try data.write(to: url)
    for limit in 1...data.count {
      let result = try BoundedTextReader.read(url, maximumBytes: limit)
      precondition("A日本語😀Z".hasPrefix(result.text))
      precondition(result.wasTruncated == (limit < data.count))
      precondition(result.text.utf8.count <= limit)
    }
    let full = try BoundedTextReader.read(url, maximumBytes: data.count)
    precondition(full.text == "A日本語😀Z" && !full.wasTruncated)
    for suffix: [UInt8] in [[0xFF], [0x80], [0xE0, 0x80], [0xED, 0xA0], [0xF4, 0x90], [0xE3, 0x81]] {
      let malformed = Data([0x41] + suffix)
      try malformed.write(to: url)
      do { _ = try BoundedTextReader.read(url, maximumBytes: 64); preconditionFailure("Malformed UTF-8 accepted") }
      catch BoundedTextReader.Failure.invalidUTF8 {}
    }
    precondition(BoundedTextReader.decodeUTF8(Data([0x41, 0xE3, 0x81]), allowingIncompleteTail: true) == "A")
    precondition(BoundedTextReader.decodeUTF8(Data([0x41, 0xFF]), allowingIncompleteTail: true) == nil)
    precondition(BoundedTextReader.decodeUTF8(Data([0x41, 0xE3, 0x81])) == nil)
    let link = root.appendingPathComponent("link.txt")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
    for invalid in [link, root, URL(string: "https://example.com/note.txt")!] {
      do { _ = try BoundedTextReader.read(invalid, maximumBytes: 64); preconditionFailure("Non-local/regular file accepted") }
      catch BoundedTextReader.Failure.invalidFile {}
    }
    let canceled = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      do { _ = try BoundedTextReader.read(url, maximumBytes: 64); return false }
      catch is CancellationError { return true }
      catch { return false }
    }
    let stopped = await canceled.value
    precondition(stopped)

    let record = UUID(), other = UUID(), project = UUID(), foreignProject = UUID()
    let file = AIQueryScope.file(record), workspace = AIQueryScope.space(project)
    precondition(file.includes(recordID: record, projectID: foreignProject))
    precondition(!file.includes(recordID: other, projectID: project))
    precondition(workspace.includes(recordID: record, projectID: project))
    precondition(!workspace.includes(recordID: record, projectID: foreignProject))
    precondition(!workspace.includes(recordID: record, projectID: nil))
    for scope in [file, workspace] {
      precondition(scope.includesTask(parentRecordID: record, recordIDs: [record]))
      precondition(!scope.includesTask(parentRecordID: other, recordIDs: [record]))
      precondition(!scope.includesTask(parentRecordID: nil, recordIDs: [record]))
    }
    precondition(AIQueryScope.global.includesTask(parentRecordID: nil, recordIDs: []))
    let attachment = AIAttachment(id: UUID(), name: "note.txt", url: url)
    let prepared = PreparedAIAttachment(id: attachment.id, name: attachment.name, url: url, text: "本文")
    precondition(prepared.matches(attachment))
    precondition(!prepared.matches(AIAttachment(id: UUID(), name: attachment.name, url: url)))
    precondition(!prepared.matches(AIAttachment(id: attachment.id, name: attachment.name, url: link)))
    print("AttachmentScopeChecks: passed (bounded UTF-8, malformed endings, local file isolation, cancellation, record/project/task boundaries, prepared identity)")
  }
}
