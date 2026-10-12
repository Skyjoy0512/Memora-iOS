import Foundation

@main
struct ShareInboxChecks {
  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("share-check-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let queue = ShareInboxQueue(root: root)
    let project = ShareInboxProject(id: UUID(), name: "長い日本語プロジェクト")
    try await queue.updateProjects([project])
    let projects = try await queue.projects()
    precondition(projects == [project])
    let id = UUID()
    let draft = try await queue.draft(id)
    let empty = try await queue.requests()
    precondition(empty.isEmpty)
    let fixture = root.appendingPathComponent("original.txt")
    try Data("共有メモ".utf8).write(to: fixture)
    let name = try ShareInboxQueue.stageFile(fixture, in: draft)
    let items = [ShareInboxItem(kind: .link, title: "記事", value: "https://example.com/plan"),
                 ShareInboxItem(kind: .file, title: "原本.txt", value: name),
                 ShareInboxItem(kind: .text, title: "メモ", value: "旅行について相談する")]
    let request = ShareInboxRequest(id: id, projectID: project.id, items: items)
    try await queue.publish(request)
    let reopened = ShareInboxQueue(root: root)
    let restored = try await reopened.requests()
    precondition(restored == [request])
    let file = try await reopened.file(name, requestID: id)
    let contents = try Data(contentsOf: file)
    precondition(contents == Data("共有メモ".utf8))
    for path in ["../original.txt", "/original.txt", "bad\\file", ".", ""] {
      do { _ = try await queue.file(path, requestID: id); preconditionFailure("unsafe reference") } catch {}
    }
    let escape = file.deletingLastPathComponent().appendingPathComponent("escape.txt")
    try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: fixture)
    do { _ = try await queue.file("escape.txt", requestID: id); preconditionFailure("symlink accepted") } catch {}
    try FileManager.default.removeItem(at: escape)
    let interruptedID = UUID()
    _ = try await queue.draft(interruptedID)
    let afterInterrupt = try await queue.requests()
    precondition(afterInterrupt == [request])
    try await queue.remove(interruptedID, draft: true)
    let invalidID = UUID()
    _ = try await queue.draft(invalidID)
    do {
      try await queue.publish(ShareInboxRequest(id: invalidID, projectID: project.id, items: [ShareInboxItem(kind: .link, title: "不正", value: "file:///secret")]))
      preconditionFailure("unsafe scheme published")
    } catch {}
    try await queue.remove(invalidID, draft: true)
    let oversized = root.appendingPathComponent("large.bin")
    FileManager.default.createFile(atPath: oversized.path, contents: nil)
    let writer = try FileHandle(forWritingTo: oversized)
    try writer.truncate(atOffset: UInt64(ShareInboxQueue.maximumFileBytes + 1))
    try writer.close()
    do { _ = try ShareInboxQueue.stageFile(oversized, in: draft); preconditionFailure("oversized file accepted") } catch {}
    try FileManager.default.removeItem(at: oversized)
    let manyID = UUID()
    _ = try await queue.draft(manyID)
    do {
      let many = (0..<11).map { ShareInboxItem(kind: .text, title: "\($0)", value: "本文") }
      try await queue.publish(ShareInboxRequest(id: manyID, projectID: project.id, items: many))
      preconditionFailure("too many items accepted")
    } catch {}
    try await queue.remove(manyID, draft: true)
    let corruptID = UUID()
    _ = try await queue.draft(corruptID)
    try await queue.publish(ShareInboxRequest(id: corruptID, projectID: project.id, items: [ShareInboxItem(kind: .text, title: "破損テスト", value: "本文")]))
    try Data("broken manifest".utf8).write(to: root.appendingPathComponent(corruptID.uuidString).appendingPathComponent("manifest.json"))
    let inspection = try await queue.inspect()
    precondition(inspection.requests == [request] && inspection.invalidIDs == [corruptID])
    try await queue.remove(corruptID)
    try await queue.remove(id)
    try await queue.remove(id)
    let final = try await queue.requests()
    precondition(final.isEmpty && FileManager.default.fileExists(atPath: fixture.path))
    print("ShareInboxChecks: passed (atomic publication, reopen, file bytes, interrupted drafts, unsafe paths, symlinks, scheme rejection, targeted cleanup)")
  }
}
