import Foundation

@main
struct ProjectSourceReadChecks {
  static func main() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectSourceReadChecks-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let name = "evidence.json"
    let url = root.appendingPathComponent(name)
    let expected = [ProjectSourceText(text: "会議の結論", page: 2, time: nil)]
    let encoded = try JSONEncoder().encode(expected)
    try encoded.write(to: url)
    let actual = try await ProjectSourceTextReader.readAsync(name, in: root)
    precondition(actual == expected)
    for invalid in ["../evidence.json", "", "/tmp/evidence.json", "missing.json"] {
      do { _ = try ProjectSourceTextReader.read(invalid, in: root); preconditionFailure("Invalid reference accepted") }
      catch {}
    }
    let link = root.appendingPathComponent("alias.json")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
    do { _ = try ProjectSourceTextReader.read("alias.json", in: root); preconditionFailure("Symlink accepted") }
    catch ProjectSourceFiles.Failure.invalidFile {}
    try FileManager.default.createDirectory(at: root.appendingPathComponent("folder.json"), withIntermediateDirectories: true)
    do { _ = try ProjectSourceTextReader.read("folder.json", in: root); preconditionFailure("Directory accepted") }
    catch ProjectSourceFiles.Failure.invalidFile {}
    let padding = Data(repeating: 0x20, count: ProjectSourceTextReader.maximumBytes - encoded.count)
    try (encoded + padding).write(to: url)
    let exact = try ProjectSourceTextReader.read(name, in: root)
    precondition(exact == expected)
    let writer = try FileHandle(forWritingTo: url)
    try writer.truncate(atOffset: UInt64(ProjectSourceTextReader.maximumBytes + 1))
    try writer.close()
    do { _ = try await ProjectSourceTextReader.readAsync(name, in: root); preconditionFailure("Oversized source accepted") }
    catch ProjectSourceFiles.Failure.invalidFile {}
    try Data("{broken}".utf8).write(to: url)
    do { _ = try ProjectSourceTextReader.read(name, in: root); preconditionFailure("Malformed source accepted") }
    catch is DecodingError {}
    try encoded.write(to: url)
    let job = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      do { _ = try await ProjectSourceTextReader.readAsync(name, in: root); return false }
      catch is CancellationError { return true }
      catch { return false }
    }
    let cancelled = await job.value
    precondition(cancelled)
    print("ProjectSourceReadChecks: passed (real local evidence, async cancellation, byte limit, invalid/path/symlink/directory rejection)")
  }
}
