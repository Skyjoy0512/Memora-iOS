import Foundation

@main
struct OfficeDocumentChecks {
  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    func read(_ name: String) throws -> OfficeDocumentExtraction.Result {
      try OfficeDocumentExtraction.read(root.appendingPathComponent(name))
    }
    let expected = ["会議の決定 & 次の仕事\tAlpha\nBeta", "担当: Ken"]
    for name in ["valid.docx", "stored.docx", "descriptor.docx", "strict.docx"] {
      let result = try read(name)
      precondition(result.blocks.map(\.text) == expected, "Word text/order/entities/deletions: \(name)")
      precondition(result.blocks.allSatisfy { $0.page == nil && $0.time == nil })
    }
    let slides = try read("ordered.pptx")
    precondition(slides.blocks.map(\.text) == ["スライド 1\nCONTENT 2", "スライド 2\nCONTENT 1"])
    let cells = try read("ordered.xlsx")
    precondition(cells.blocks.map(\.text) == ["シート: 今月\nA1: 今月の売上\nB1: 1200", "シート: 先月\nA1: Budget 2026\nB1: TRUE\nC1: 42"])
    precondition(cells.blocks.allSatisfy { $0.text.hasPrefix("シート: ") }, "Sheet context must accompany row evidence")
    precondition(cells.notice.contains("数式の再計算") && cells.notice.contains("非表示のシート"))
    let limited = try read("text-limit.docx")
    precondition(limited.blocks.map(\.text).joined().count == 80_000 && limited.notice.contains("80,000"))
    let unicode = try read("unicode-byte-limit.docx")
    precondition(unicode.blocks.reduce(0) { $0 + $1.text.utf8.count } <= 256 * 1024)
    let encoded = try JSONEncoder().encode(unicode.blocks)
    precondition(encoded.count < 2 * 1024 * 1024 && !unicode.blocks.isEmpty && unicode.notice.contains("256KB"))
    let restored = try JSONDecoder().decode([ProjectSourceText].self, from: encoded)
    precondition(restored == unicode.blocks)
    for name in ["traversal.docx", "entity.docx", "utf16-entity.docx", "depth.docx", "nodes.docx", "part-bomb.docx",
                 "external.docx", "relationship-escape.docx", "missing.docx", "macro.docx", "bad-string-index.xlsx",
                 "external-slide.pptx", "crc.docx", "truncated.docx", "encrypted.docx", "symlink.docx", "duplicate.docx"] {
      do { _ = try read(name); preconditionFailure("Unsafe package accepted: \(name)") }
      catch is OfficeArchiveReader.Failure {}
    }
    // Exercise offsets and truncated headers without producing files or extracting entries.
    for count in 0..<100 {
      do { _ = try OfficeArchiveReader(data: Data(repeating: 0x50, count: count)); preconditionFailure("Garbage accepted") }
      catch is OfficeArchiveReader.Failure {}
    }
    let cancelled = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      do { _ = try OfficeDocumentExtraction.read(root.appendingPathComponent("valid.docx")); return false }
      catch is CancellationError { return true }
      catch { return false }
    }
    let didCancel = await cancelled.value
    precondition(didCancel)
    print("OfficeDocumentChecks: passed (real stored/DEFLATE/descriptor OOXML, Japanese text, slide/sheet order, cached cells, strict namespace, bounds, cancellation, corrupt/hostile packages; no network)")
  }
}
