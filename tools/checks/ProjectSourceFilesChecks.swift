import Foundation

@main
struct ProjectSourceFilesChecks {
  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("MemoraFileChecks-\(UUID())")
    let managed = root.appendingPathComponent("managed")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let original = root.appendingPathComponent("note.txt")
    try Data("保存した本文".utf8).write(to: original)
    let store = ProjectSourceFiles(directory: managed)
    let first = try await store.copy(original)
    let second = try await store.copy(original)
    precondition(first.reference != second.reference && first.fingerprint == second.fingerprint)
    let firstURL = ProjectSourceFiles.resolve(first.reference, in: managed)!
    let copiedText = try String(contentsOf: firstURL, encoding: .utf8)
    precondition(copiedText == "保存した本文")
    for name in ["../note.txt", "/tmp/note.txt", "a/b", "a\\b", "..", "", "a\0b"] {
      precondition(ProjectSourceFiles.resolve(name, in: managed) == nil)
    }
    let escaped = managed.appendingPathComponent("escaped.txt")
    try FileManager.default.createSymbolicLink(at: escaped, withDestinationURL: original)
    precondition(ProjectSourceFiles.resolve("escaped.txt", in: managed) == nil)
    let large = root.appendingPathComponent("large.pdf")
    FileManager.default.createFile(atPath: large.path, contents: nil)
    let handle = try FileHandle(forWritingTo: large)
    try handle.truncate(atOffset: UInt64(ProjectSourceFiles.maximumFileBytes + 1))
    try handle.close()
    do { _ = try await store.copy(large); preconditionFailure("Accepted oversized file") }
    catch ProjectSourceFiles.Failure.tooLarge {}
    await store.remove([first.reference])
    precondition(!FileManager.default.fileExists(atPath: firstURL.path))
    precondition(FileManager.default.fileExists(atPath: original.path))
    precondition(FileManager.default.fileExists(atPath: ProjectSourceFiles.resolve(second.reference, in: managed)!.path))
    print("ProjectSourceFilesChecks: passed (bounded import, content fingerprint, path/symlink isolation, selective deletion)")
  }
}
