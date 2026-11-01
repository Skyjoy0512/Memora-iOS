import AppKit
import CryptoKit
import Darwin
import Foundation
import PDFKit
import SQLite3

@main struct PDFPartitionChecks {
  @MainActor static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    if CommandLine.arguments.contains("--abrupt-copy") {
      try await abruptCopy(root: root, commit: CommandLine.arguments.contains("--commit"))
      _exit(0)
    }
    let original = root.appendingPathComponent("205-page-source.pdf")
    try makePDF(original)
    let before = try Data(contentsOf: original)
    let stage = root.appendingPathComponent("partitions", isDirectory: true)
    let partition = try PDFSourcePartition.prepare(original, directory: stage)
    defer { partition.cleanup() }
    precondition(partition.parts.map(\.firstPage) == [1, 101, 201])
    precondition(partition.parts.map(\.lastPage) == [100, 200, 205])
    precondition(partition.originalPageCount == 205 && partition.originalName == original.lastPathComponent)
    precondition(partition.fingerprint == SHA256.hash(data: before).map { String(format: "%02x", $0) }.joined())
    for part in partition.parts {
      let document = PDFDocument(url: part.url)!
      precondition(document.pageCount == part.lastPage - part.firstPage + 1)
      precondition(document.page(at: 0)!.string!.contains("ORIGINAL PAGE \(part.firstPage)"))
      precondition(document.page(at: document.pageCount - 1)!.string!.contains("ORIGINAL PAGE \(part.lastPage)"))
      precondition(document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String == "Partition author")
    }
    let second = PDFDocument(url: partition.parts[1].url)!
    precondition(second.page(at: 3)!.annotations.contains { ($0.action as? PDFActionURL)?.url?.absoluteString == "https://example.com/evidence" })
    let last = PDFDocument(url: partition.parts[2].url)!
    precondition(last.page(at: 0)!.string!.contains("NEBULA 7264"))
    expect(try Data(contentsOf: original) == before)
    let orphan = stage.appendingPathComponent("partition-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: false)
    try Data().write(to: orphan.appendingPathComponent(".lease"))
    let other = try PDFSourcePartition.prepare(original, directory: stage)
    precondition(!FileManager.default.fileExists(atPath: orphan.path))
    precondition(partition.parts.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
    precondition(other.cleanup())
    try await importChecks(root: root, original: original, partition: partition)
    try await recoveryChecks(root: root)
    try refusalChecks(root: root, stage: stage, original: original)
    let cancelled = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      return try PDFSourcePartition.prepare(original, directory: stage)
    }
    do { _ = try await cancelled.value; preconditionFailure("Cancelled partition started") }
    catch is CancellationError {}
    expect(try Data(contentsOf: original) == before)
    precondition(partition.cleanup())
    print("PDFPartitionChecks: PASS. Real205-page PDF ->3 native parts; atomic registration/rollback/dedup/privacy; abrupt subprocess exit before/after commit, provisional copy/stage recovery, live-lock protection, unrelated-file preservation, corrupt journal and failed cleanup retention. No iOS/UI/LLM/resource-profile claim.")
  }

  @MainActor private static func importChecks(root: URL, original: URL, partition: PDFSourcePartition) async throws {
    let model = try MemoraModel(storeURL: root.appendingPathComponent("partition-import.sqlite"))
    let project = MemoraSpace(id: UUID(), name: "Partition project", symbol: "folder")
    model.spaces = [project]
    let receipt = try await ProjectSourceFiles.shared.copy(original)
    var privacy = RecordPrivacy()
    privacy.classification = .sensitive
    privacy.blocksOneTimeCloudSummary = true
    let source = ProjectSource(projectID: project.id, kind: .pdf, title: "Confidential original",
      localFileReference: receipt.reference, contentFingerprint: receipt.fingerprint, processingStatus: .ready,
      privacy: privacy, summary: "Original summary stays")
    precondition(model.storeProjectSource(source))
    let context = LocalImportContext(projectID: project.id, in: model)!
    let gate = PartitionWorkGate()
    model.preparationHook = { _ in await gate.wait() }
    let ids = try await model.importPDFParts(partition, context: context, originalSource: source)!
    precondition(ids.count == 3 && model.projectSources.count == 4)
    let reopened = LocalStore(fileURL: model.storeURL)
    try reopened.prepare()
    guard case .data(let savedData) = reopened.readOutcome(MemoraModel.StorageKey.projectSources) else { preconditionFailure("Missing saved group") }
    let stored = try JSONDecoder().decode([ProjectSource].self, from: savedData)
    precondition(stored.count == 4 && model.source(id: source.id) == source)
    for (index, id) in ids.enumerated() {
      let part = model.source(id: id)!
      precondition(part.privacy == privacy && part.projectID == project.id)
      precondition(part.title.hasPrefix(source.title) && part.metadata?["partitionFirstPage"] == String(partition.parts[index].firstPage))
      precondition(PDFDocument(url: ProjectSourceFiles.resolve(part.localFileReference!)!)?.pageCount == partition.parts[index].lastPage - partition.parts[index].firstPage + 1)
    }
    await gate.entered()
    for _ in 0..<100 { await Task.yield() }
    precondition(model.preparedSourceIDs.count == 1, "Partition summaries must not start concurrently")
    let filesBefore = try files()
    let again = try await model.importPDFParts(partition, context: context, originalSource: source)
    precondition(again == ids && model.projectSources.count == 4)
    expect(try files() == filesBefore)
    var changed = source
    changed.privacy.classification = .general
    precondition(model.storeProjectSource(changed))
    do {
      _ = try await model.importPDFParts(partition, context: context, originalSource: changed)
      preconditionFailure("Different privacy reused existing parts")
    } catch PDFSourcePartitionImportFailure.privacyChanged {}
    precondition(model.storeProjectSource(source))
    await gate.resume()
    let jobs = Array(model.sourcePreparationJobs.values.map(\.task))
    for job in jobs { await job.value }
    precondition(model.preparedSourceIDs == ids)

    model.aiWorkspaceGeneration = UUID()
    expect(try await model.importPDFParts(partition, context: context) == nil)
    expect(try files() == filesBefore)
    let failing = try MemoraModel(storeURL: root.appendingPathComponent("partition-failure.sqlite"))
    let personal = LocalImportContext(in: failing)!
    try execute("CREATE TRIGGER reject_partition BEFORE INSERT ON documents WHEN NEW.key = '\(PDFSourceCopyJournal.key)' AND EXISTS(SELECT 1 FROM documents WHERE key = 'memoraProjectSources') BEGIN SELECT RAISE(ABORT, 'partition journal commit check'); END;", file: failing.storeURL)
    let failed = try await failing.importPDFParts(partition, context: personal)
    precondition(failed == nil && failing.projectSources.isEmpty && failing.sourcePreparationJobs.isEmpty)
    expect(try files() == filesBefore)
    try execute("DROP TRIGGER reject_partition;", file: failing.storeURL)
    var missing = partition
    missing.parts[1].url = root.appendingPathComponent("missing-part.pdf")
    do { _ = try await failing.importPDFParts(missing, context: personal); preconditionFailure("Missing part was accepted") }
    catch {}
    precondition(failing.projectSources.isEmpty && failing.sourcePreparationJobs.isEmpty)
    expect(try files() == filesBefore)
  }

  @MainActor private static func abruptCopy(root: URL, commit: Bool) async throws {
    let store = LocalStore(fileURL: root.appendingPathComponent("crash.sqlite"))
    try store.prepare()
    let journal = PDFSourceCopyJournal(store: store)
    let lease = try journal.begin(count: 2)
    let input = root.appendingPathComponent("abrupt-input.pdf")
    try Data("Abrupt process fixture".utf8).write(to: input)
    let copied = try await ProjectSourceFiles.shared.copy(input, named: lease.references[0])
    let stage = ProjectSourceFiles.directory.appendingPathComponent(".stage-" + lease.references[1])
    try Data("Interrupted partial copy".utf8).write(to: stage)
    if commit {
      let source = ProjectSource(kind: .pdf, title: "Committed before exit", localFileReference: copied.reference)
      try store.applyBatch(writes: [
        (key: "committedSources", data: try JSONEncoder().encode([source])),
        try journal.committedDocument(lease, retaining: [copied.reference])
      ], removing: [])
    }
    // Do not run deinit or normal finish: this leaves the actual SQLite ledger
    // and copies for the parent process to recover after OS lock release.
    withExtendedLifetime(lease) { _exit(0) }
  }

  @MainActor private static func recoveryChecks(root: URL) async throws {
    let storeURL = root.appendingPathComponent("crash.sqlite")
    let store = LocalStore(fileURL: storeURL)
    try store.prepare()
    let journal = PDFSourceCopyJournal(store: store)
    let legacy = ProjectSourceFiles.directory.appendingPathComponent("legacy-user.pdf")
    try Data("Never sweep unjournaled data".utf8).write(to: legacy)
    let before = try files()
    for commit in [false, true] {
      let child = Process()
      child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
      child.arguments = [root.path, "--abrupt-copy"] + (commit ? ["--commit"] : [])
      try child.run()
      child.waitUntilExit()
      precondition(child.terminationStatus == 0)
      let pending = try ledger(store)
      precondition(pending.count == 1)
      let staged = try files().subtracting(before)
      precondition(staged.contains { $0.hasPrefix(".stage-pdfcopy-") })
      try await journal.recover()
      expect(try ledger(store).isEmpty)
      if commit {
        guard case .data(let data) = store.readOutcome("committedSources") else { preconditionFailure("Lost committed source") }
        let saved = try JSONDecoder().decode([ProjectSource].self, from: data)
        let reference = saved[0].localFileReference!
        precondition(FileManager.default.fileExists(atPath: ProjectSourceFiles.resolve(reference)!.path))
        expect(try files() == before.union([reference]))
        await ProjectSourceFiles.shared.remove([reference])
      } else {
        expect(try files() == before)
      }
    }
    var live: PDFSourceCopyLease? = try journal.begin(count: 1)
    let liveReference = live!.references[0]
    let liveFile = ProjectSourceFiles.resolve(liveReference)!
    try Data("Active copy".utf8).write(to: liveFile)
    try await journal.recover()
    precondition(FileManager.default.fileExists(atPath: liveFile.path))
    live = nil
    try await journal.recover()
    precondition(!FileManager.default.fileExists(atPath: liveFile.path))

    var blocked: PDFSourceCopyLease? = try journal.begin(count: 1)
    let blockedFile = ProjectSourceFiles.resolve(blocked!.references[0])!
    try FileManager.default.createDirectory(at: blockedFile, withIntermediateDirectories: false)
    blocked = nil
    do { try await journal.recover(); preconditionFailure("Deleted an unexpected directory") } catch {}
    expect(try ledger(store).count == 1)
    precondition(FileManager.default.fileExists(atPath: blockedFile.path))
    try FileManager.default.removeItem(at: blockedFile)
    try await journal.recover()
    expect(try ledger(store).isEmpty)
    try store.write(PDFSourceCopyJournal.key, data: Data("corrupt journal".utf8))
    do { try await journal.recover(); preconditionFailure("Ignored unreadable ledger") } catch {}
    expect(try files() == before)
    try store.write(PDFSourceCopyJournal.key, data: JSONEncoder().encode([String: [String]]()))
    precondition(FileManager.default.fileExists(atPath: legacy.path))
  }

  @MainActor private static func ledger(_ store: LocalStore) throws -> [String: [String]] {
    guard case .data(let data) = store.readOutcome(PDFSourceCopyJournal.key) else { preconditionFailure("Missing journal") }
    return try JSONDecoder().decode([String: [String]].self, from: data)
  }

  private static func refusalChecks(root: URL, stage: URL, original: URL) throws {
    let form = PDFDocument(url: original)!
    form.page(at: 0)!.addAnnotation(PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 50, height: 20), forType: .widget, withProperties: nil))
    let formURL = root.appendingPathComponent("form.pdf")
    precondition(form.write(to: formURL))
    do { _ = try PDFSourcePartition.prepare(formURL, directory: stage); preconditionFailure("Form semantics lost") }
    catch PDFSourcePartitionFailure.interactiveDocument {}
    let protected = root.appendingPathComponent("encrypted.pdf")
    precondition(PDFDocument(url: original)!.write(to: protected, withOptions: [.ownerPasswordOption: "owner", .userPasswordOption: "reader"]))
    do { _ = try PDFSourcePartition.prepare(protected, directory: stage); preconditionFailure("Encrypted input accepted") }
    catch PDFSourcePartitionFailure.encrypted {}
    let link = root.appendingPathComponent("linked.pdf")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
    do { _ = try PDFSourcePartition.prepare(link, directory: stage); preconditionFailure("Symlink accepted") }
    catch PDFSourcePartitionFailure.invalidFile {}
  }

  private static func makePDF(_ url: URL) throws {
    var box = CGRect(x: 0, y: 0, width: 600, height: 800)
    let context = CGContext(consumer: CGDataConsumer(url: url as CFURL)!, mediaBox: &box, nil)!
    for page in 1...205 {
      context.beginPDFPage(nil)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
      let text = "ORIGINAL PAGE \(page)" + (page == 201 ? " NEBULA 7264" : "")
      (text as NSString).draw(at: CGPoint(x: 40, y: 700), withAttributes: [.font: NSFont.systemFont(ofSize: 22)])
      NSGraphicsContext.restoreGraphicsState()
      context.endPDFPage()
    }
    context.closePDF()
    let document = PDFDocument(url: url)!
    document.documentAttributes = [PDFDocumentAttribute.authorAttribute: "Partition author"]
    let link = PDFAnnotation(bounds: CGRect(x: 40, y: 650, width: 200, height: 30), forType: .link, withProperties: nil)
    link.action = PDFActionURL(url: URL(string: "https://example.com/evidence")!)
    document.page(at: 103)!.addAnnotation(link)
    precondition(document.write(to: url))
  }

  private static func files() throws -> Set<String> {
    Set(try FileManager.default.contentsOfDirectory(atPath: ProjectSourceFiles.directory.path))
  }

  private static func expect(_ value: Bool) { precondition(value) }

  private static func execute(_ sql: String, file: URL) throws {
    var database: OpaquePointer?
    precondition(sqlite3_open(file.path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    precondition(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
  }
}

private actor PartitionWorkGate {
  private var continuation: CheckedContinuation<Void, Never>?
  private var didEnter = false
  private var isReleased = false
  func wait() async {
    didEnter = true
    if !isReleased { await withCheckedContinuation { continuation = $0 } }
  }
  func entered() async { while !didEnter { await Task.yield() } }
  func resume() { isReleased = true; continuation?.resume(); continuation = nil }
}
