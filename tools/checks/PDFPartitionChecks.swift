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
    try await largeFileRouteChecks(root: root)
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

  @MainActor private static func largeFileRouteChecks(root: URL) async throws {
    let large = root.appendingPathComponent("large-provider-file")
    try makeLargePDF(large, pages: 205)
    precondition(PDFDocument(url: large)?.pageCount == 205)
    expect(try PDFSourcePartitioning.requiresPartition(large))
    let partition = try await PDFSourcePartitioning.prepare(large, maximumParts: 3)
    defer { partition.cleanup() }
    precondition(partition.parts.map(\.firstPage) == [1, 101, 201])
    precondition(PDFDocument(url: partition.parts[2].url)?.page(at: 4)?.string?.contains("LATE PAGE 205") == true)
    do {
      _ = try await PDFSourcePartitioning.prepare(large, maximumParts: 2)
      preconditionFailure("Conversation part budget ignored")
    } catch PDFSourcePartitionFailure.partLimit {}
    let model = try MemoraModel(storeURL: root.appendingPathComponent("large-entry.sqlite"))
    let context = LocalImportContext(in: model)!
    let ids = try await model.importInformationSources(large, context: context)!
    precondition(ids.count == 3 && model.projectSources.count == 3)
    let again = try await model.importInformationSources(large, context: context)
    precondition(again == ids && model.projectSources.count == 3)

    // The same part saved from a conversation can have different native PDF
    // bytes. Its original fingerprint/range must still find the existing source.
    let altered = root.appendingPathComponent("conversation-part.pdf")
    try FileManager.default.copyItem(at: partition.parts[0].url, to: altered)
    let writer = try FileHandle(forWritingTo: altered)
    try writer.seekToEnd(); try writer.write(contentsOf: Data("\n".utf8)); try writer.close()
    let saved = try await model.importProjectFile(altered, projectID: nil, importContext: context,
      waitsForPreparation: false, sourceMetadata: partition.metadata(for: partition.parts[0]))
    precondition(saved == ids[0] && model.projectSources.count == 3)
    let receipt = (key: "test.sharedPDFReceipt", data: Data("registered".utf8))
    let shared = try await model.importPDFParts(partition, context: context, registrationReceipt: { _ in receipt })
    precondition(shared == ids && model.projectSources.count == 3)
    guard case .data(let bytes) = model.store.readOutcome(receipt.key) else { preconditionFailure("Missing atomic receipt") }
    precondition(bytes == receipt.data)
    let failing = try MemoraModel(storeURL: root.appendingPathComponent("large-receipt-failure.sqlite"))
    let before = try files()
    try execute("CREATE TRIGGER reject_receipt BEFORE INSERT ON documents WHEN NEW.key = '\(receipt.key)' BEGIN SELECT RAISE(ABORT, 'receipt check'); END;", file: failing.storeURL)
    let rejected = try await failing.importPDFParts(partition, context: LocalImportContext(in: failing)!, registrationReceipt: { _ in receipt })
    precondition(rejected == nil && failing.projectSources.isEmpty && failing.sourcePreparationJobs.isEmpty)
    expect(try files() == before)
    guard case .missing = failing.store.readOutcome(receipt.key),
          case .missing = failing.store.readOutcome(MemoraModel.StorageKey.projectSources) else { preconditionFailure("Partial share registration") }
    let fake = root.appendingPathComponent("fake-large.pdf")
    try FileManager.default.copyItem(at: large, to: fake)
    let fakeWriter = try FileHandle(forWritingTo: fake)
    try fakeWriter.write(contentsOf: Data("FAKE!".utf8)); try fakeWriter.close()
    expect(try !PDFSourcePartitioning.requiresPartition(fake))
    let link = root.appendingPathComponent("large-link.pdf")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: large)
    do { _ = try PDFSourcePartitioning.requiresPartition(link); preconditionFailure("Large symlink admitted") } catch {}
    try await sharedLargeFileChecks(root: root, large: large)
    print("PASS real >50MB 205-page PDF automatic intake/late-page content, native conversation part budget, cross-entry metadata dedup, atomic shared receipt/rollback, magic and symlink guards")
  }

  @MainActor private static func sharedLargeFileChecks(root: URL, large: URL) async throws {
    let queueRoot = root.appendingPathComponent("share-pdf-queue")
    ShareInboxConfiguration.root = queueRoot
    defer { ShareInboxConfiguration.root = nil }
    let queue = ShareInboxQueue(root: queueRoot)
    let model = try MemoraModel(storeURL: root.appendingPathComponent("shared-route.sqlite"))
    let project = MemoraSpace(id: UUID(), name: "Share target", symbol: "folder")
    model.spaces = [project]
    let requestID = UUID(), draft = try await queue.draft(requestID)
    let name = try ShareInboxQueue.stageFile(large, in: draft)
    let pdf = ShareInboxItem(kind: .file, title: "Shared original PDF", value: name)
    let note = ShareInboxItem(kind: .text, title: "FAIL_SECOND_ITEM", value: "Saved after retry")
    let request = ShareInboxRequest(id: requestID, projectID: project.id, items: [pdf, note])
    try await queue.publish(request)
    try execute("CREATE TRIGGER reject_second BEFORE INSERT ON documents WHEN NEW.key = 'memoraProjectSources' AND CAST(NEW.data AS TEXT) LIKE '%FAIL_SECOND_ITEM%' BEGIN SELECT RAISE(ABORT, 'second item check'); END;", file: model.storeURL)
    await model.importShareInbox()
    precondition(model.projectSources.count == 3 && model.shareInboxRequests.count == 1 && model.shareInboxFailure != nil)
    var ids = Set(model.projectSources.map(\.id))
    for var source in model.projectSources {
      source.projectID = nil
      precondition(model.storeProjectSource(source))
    }
    await model.importShareInbox()
    precondition(Set(model.projectSources.map(\.id)) == ids && model.projectSources.allSatisfy { $0.projectID == nil })
    // Simulate restoring an earlier source snapshot while the failed request
    // remains in the Inbox. Its receipt must not suppress the missing PDF.
    precondition(model.persistNow([ProjectSource](), forKey: MemoraModel.StorageKey.projectSources))
    model.projectSources = []
    await model.importShareInbox()
    precondition(model.projectSources.count == 3 && Set(model.projectSources.map(\.id)).isDisjoint(with: ids))
    ids = Set(model.projectSources.map(\.id))
    for var source in model.projectSources {
      source.projectID = nil
      precondition(model.storeProjectSource(source))
    }
    try execute("DROP TRIGGER reject_second;", file: model.storeURL)
    await model.importShareInbox()
    precondition(model.projectSources.count == 4 && model.shareInboxRequests.isEmpty && model.shareInboxFailure == nil)
    precondition(model.projectSources.filter { ids.contains($0.id) }.allSatisfy { $0.projectID == nil })
    guard case .missing = model.store.readOutcome("memora.share.pdfReceipt." + pdf.id.uuidString) else { preconditionFailure("Receipt not cleared after queue removal") }
    let pending = try await queue.inspect()
    precondition(pending.requests.isEmpty && pending.invalidIDs.isEmpty)
    precondition(FileManager.default.fileExists(atPath: large.path))
    print("PASS production share queue -> native PDF parts -> SQLite, later-item failure retains queue; receipt prevents duplicate/re-filing, earlier snapshot restore reimports missing group; final success clears queue/receipt")
  }

  private static func makeLargePDF(_ url: URL, pages: Int) throws {
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let file = try FileHandle(forWritingTo: url)
    defer { try? file.close() }
    var offsets: [UInt64] = [0]
    func write(_ text: String) throws { try file.write(contentsOf: Data(text.utf8)) }
    func object(_ number: Int, _ body: String) throws {
      precondition(number == offsets.count)
      offsets.append(try file.offset())
      try write("\(number) 0 obj\n\(body)\nendobj\n")
    }
    try write("%PDF-1.7\n")
    try object(1, "<< /Type /Catalog /Pages 2 0 R >>")
    try object(2, "<< /Type /Pages /Count \(pages) /Kids [" + (0..<pages).map { "\(3 + 2 * $0) 0 R" }.joined(separator: " ") + "] >>")
    let font = 3 + 2 * pages
    for page in 0..<pages {
      try object(3 + 2 * page, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Resources << /Font << /F1 \(font) 0 R >> >> /Contents \(4 + 2 * page) 0 R >>")
      let text = "BT /F1 18 Tf 40 700 Td (LATE PAGE \(page + 1)) Tj ET"
      try object(4 + 2 * page, "<< /Length \(text.utf8.count) >>\nstream\n\(text)\nendstream")
    }
    try object(font, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    offsets.append(try file.offset())
    let padding = ProjectSourceFiles.maximumFileBytes + 1
    try write("\(font + 1) 0 obj\n<< /Length \(padding) >>\nstream\n")
    try file.seek(toOffset: try file.offset() + UInt64(padding))
    try write("\nendstream\nendobj\n")
    let xref = try file.offset()
    try write("xref\n0 \(offsets.count)\n0000000000 65535 f \n")
    for offset in offsets.dropFirst() { try write(String(format: "%010llu 00000 n \n", offset)) }
    try write("trailer\n<< /Size \(offsets.count) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n")
    try file.synchronize()
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
