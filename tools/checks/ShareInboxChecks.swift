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
    try await checkPDFAdmission(projectID: project.id)
    print("ShareInboxChecks: passed (atomic publication, reopen, file bytes, interrupted drafts, unsafe paths, symlinks, scheme rejection, targeted cleanup, bounded large-PDF admission and revalidation)")
  }

  static func checkPDFAdmission(projectID: UUID) async throws {
    let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("share-pdf-check-" + UUID().uuidString)
    let root = workspace.appendingPathComponent("queue")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workspace) }
    let queue = ShareInboxQueue(root: root)
    let input = workspace.appendingPathComponent("provider-temporary-file")
    try sparseFile(input, bytes: ShareInboxQueue.maximumFileBytes + 1, pdf: true)
    let id = UUID(), draft = try await queue.draft(id)
    let name = try ShareInboxQueue.stageFile(input, in: draft, preferredExtension: "bin")
    precondition(name.hasSuffix(".pdf"), "Magic-identified PDF must not depend on the provider filename")
    let request = ShareInboxRequest(id: id, projectID: projectID, items: [.init(kind: .file, title: "PDF", value: name)])
    try await queue.publish(request)
    let reopened = ShareInboxQueue(root: root)
    let requests = try await reopened.requests()
    precondition(requests == [request])
    let staged = try await reopened.file(name, requestID: id)
    let writer = try FileHandle(forWritingTo: staged)
    try writer.write(contentsOf: Data("FAKE!".utf8))
    try writer.close()
    do { _ = try await reopened.file(name, requestID: id); preconditionFailure("Changed PDF magic accepted") } catch {}
    let inspected = try await reopened.inspect()
    precondition(inspected.requests.isEmpty && inspected.invalidIDs == [id])
    try await queue.remove(id)

    let fake = workspace.appendingPathComponent("fake.pdf")
    try sparseFile(fake, bytes: ShareInboxQueue.maximumFileBytes + 1, pdf: false)
    let fakeID = UUID(), fakeDraft = try await queue.draft(fakeID)
    do { _ = try ShareInboxQueue.stageFile(fake, in: fakeDraft); preconditionFailure("Extension-only PDF accepted") } catch {}
    let fakeFiles = try FileManager.default.contentsOfDirectory(atPath: fakeDraft.path)
    precondition(fakeFiles.isEmpty)
    try await queue.remove(fakeID, draft: true)

    // Sparse fixtures exercise admission limits without allocating huge Data buffers.
    let limitID = UUID(), limitDraft = try await queue.draft(limitID)
    try sparseFile(limitDraft.appendingPathComponent("limit.pdf"), bytes: ShareInboxQueue.maximumPDFBytes, pdf: true)
    let limitRequest = ShareInboxRequest(id: limitID, projectID: projectID, items: [.init(kind: .file, title: "Limit", value: "limit.pdf")])
    try await queue.publish(limitRequest)
    _ = try await queue.file("limit.pdf", requestID: limitID)
    try await queue.remove(limitID)

    let overID = UUID(), overDraft = try await queue.draft(overID)
    try sparseFile(overDraft.appendingPathComponent("over.pdf"), bytes: ShareInboxQueue.maximumPDFBytes + 1, pdf: true)
    do {
      try await queue.publish(.init(id: overID, projectID: projectID, items: [.init(kind: .file, title: "Over", value: "over.pdf")]))
      preconditionFailure("Oversized PDF accepted")
    } catch {}
    try await queue.remove(overID, draft: true)

    let combinedID = UUID(), combinedDraft = try await queue.draft(combinedID)
    try sparseFile(combinedDraft.appendingPathComponent("a.pdf"), bytes: 300 * 1024 * 1024, pdf: true)
    try sparseFile(combinedDraft.appendingPathComponent("b.pdf"), bytes: 201 * 1024 * 1024, pdf: true)
    do {
      try await queue.publish(.init(id: combinedID, projectID: projectID, items: [
        .init(kind: .file, title: "A", value: "a.pdf"), .init(kind: .file, title: "B", value: "b.pdf")]))
      preconditionFailure("Combined PDF budget exceeded")
    } catch {}
    try await queue.remove(combinedID, draft: true)

    let ordinaryID = UUID(), ordinaryDraft = try await queue.draft(ordinaryID)
    for name in ["a.bin", "b.bin", "c.bin"] {
      try sparseFile(ordinaryDraft.appendingPathComponent(name), bytes: 40 * 1024 * 1024, pdf: false)
    }
    do {
      try await queue.publish(.init(id: ordinaryID, projectID: projectID, items: ["a.bin", "b.bin", "c.bin"].map {
        .init(kind: .file, title: $0, value: $0)
      }))
      preconditionFailure("Ordinary aggregate limit bypassed")
    } catch {}
    do { _ = try ShareInboxQueue.stageFile(input, in: ordinaryDraft); preconditionFailure("Over-budget draft extended") } catch {}
    try await queue.remove(ordinaryID, draft: true)

    let fullID = UUID(), fullDraft = try await queue.draft(fullID)
    try sparseFile(root.appendingPathComponent("occupied"), bytes: ShareInboxQueue.maximumQueueBytes, pdf: false)
    do { _ = try ShareInboxQueue.stageFile(input, in: fullDraft); preconditionFailure("Queue budget bypassed during staging") } catch {}
    do {
      try await queue.publish(.init(id: fullID, projectID: projectID, items: [.init(kind: .text, title: "Text", value: "Text")]))
      preconditionFailure("Queue budget ignored manifest size")
    } catch {}
  }

  static func sparseFile(_ url: URL, bytes: Int, pdf: Bool) throws {
    guard FileManager.default.createFile(atPath: url.path, contents: nil) else { preconditionFailure("Fixture creation failed") }
    let file = try FileHandle(forWritingTo: url)
    defer { try? file.close() }
    if pdf { try file.write(contentsOf: Data("%PDF-1.7\n".utf8)) }
    try file.truncate(atOffset: UInt64(bytes))
  }
}
