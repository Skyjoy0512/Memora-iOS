import Foundation

@main
enum IncrementalMarkdownChecks {
  static func main() {
    let fixtures = [
      "日本語の長い回答です。" + String(repeating: "自然な読みやすさ。", count: 40),
      "# 見出し\n\n本文**強調**です。\n次の行。\n\n- 項目1\n- 項目2\n\n> 引用\n\n---\n",
      "| 項目 | 値 |\n| --- | --- |\n| 一 | 二 |\n| 三 | 四 |\n\n結論。",
      "```swift\nlet text = \"# 見出し\"\n\n- this is code\n```\n\n後続。",
      "````text\n```\n\n# literal\n````\n\n~~~txt\ncode\n~~~\n",
      "[リンク](https://example.invalid) と【資料1】\n\n終わり。",
      "未完了の [リンク](https://exam",
      "```swift\nunfinished code",
      "# 見出し\r\n\r\n日本語\r\n",
      "Cafe\u{301}と👨‍👩‍👧‍👦\n\n- [ ] 未完了\n- [x] 完了\n\n| 対象 | 値 |\n| :--- | ---: |\n| 資料 | [リンク](https://example.invalid) |\n\n~~~swift\r\nlet value = \"`\"\r\n\r\n~~~\r\n\r\n終了"
    ]
    for fixture in fixtures {
      var stream = IncrementalMarkdown()
      var text = ""
      for scalar in fixture.unicodeScalars {
        text.unicodeScalars.append(scalar)
        stream.update(text, isStreaming: true)
        let prefix = stream.settled
        stream.update(text, isStreaming: true)
        precondition(prefix == stream.settled)
      }
      stream.update(text, isStreaming: false)
      precondition(stream.blocks == MarkdownBlockParser.blocks(for: fixture), "Incremental/final mismatch: \(fixture)")
      let parsed = stream.parsedBytes
      stream.update(text, isStreaming: false)
      precondition(parsed == stream.parsedBytes)
      stream.update("置換された回答", isStreaming: false)
      precondition(stream.blocks == [.paragraph("置換された回答")])
    }
    // Network chunks need not align with lines, fences, links, or graphemes.
    // Compare every published snapshot with the settled document's real parser.
    for fixture in fixtures {
      let scalars = Array(fixture.unicodeScalars)
      for width in [1, 7, 37] {
        var stream = IncrementalMarkdown()
        var text = ""
        var offset = 0
        while offset < scalars.count {
          let end = min(offset + width, scalars.count)
          text.unicodeScalars.append(contentsOf: scalars[offset..<end])
          let settled = stream.settled
          stream.update(text, isStreaming: true)
          precondition(Array(stream.settled.prefix(settled.count)) == settled, "Previously settled blocks changed")
          precondition(stream.blocks == MarkdownBlockParser.sourcedBlocks(for: text).map(\.block), "Published snapshot differs from final renderer")
          offset = end
        }
        let beforeFinish = stream.blocks
        stream.update(text, isStreaming: false)
        precondition(stream.blocks == beforeFinish, "Completion changed block structure")
      }
    }
    var document = IncrementalMarkdown()
    document.update("確定した段落\n\n途中", isStreaming: true)
    let settled = document.settled
    document.update("確定した段落\n\n途中の続き", isStreaming: true)
    precondition(document.settled == settled && settled == [.paragraph("確定した段落")])
    let code = MarkdownBlockParser.blocks(for: "```\n# literal\n\n| no | table |\n```")
    precondition(code == [.code(language: "", text: "# literal\n\n| no | table |")])
    let replacement = MarkdownBlockWriter.source(of: .code(language: "text", text: "```\ncontent"), original: [])
    precondition(MarkdownBlockParser.blocks(for: replacement.joined(separator: "\n")) == [.code(language: "text", text: "```\ncontent")])
    print("IncrementalMarkdownChecks: passed (1/7/37-scalar chunks, every live prefix matches final parser, stable settled blocks, no completion structure change, Japanese/combining/emoji/CRLF, headings/lists/quotes/tables/fences/links, replacement, no replay parse)")
  }
}
