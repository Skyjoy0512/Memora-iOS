#if DEBUG
import Foundation

/// Quick checks that run in debug builds only, until the project has a test
/// target. They cover the pieces most likely to break silently: the markdown
/// round trip used by inline editing, and the draft store. Failures are logged
/// rather than fatal, so a debug build never crashes over a check.
@MainActor
enum SelfChecks {
  static func run() {
    checkMarkdownRoundTrip("**太字**", name: "bold")
    checkMarkdownRoundTrip("*斜体*", name: "italic")
    checkMarkdownRoundTrip("`code`", name: "code")
    checkMarkdownRoundTrip("~~取り消し~~", name: "strikethrough")
    checkMarkdownRoundTrip("[リンク](https://example.com)", name: "link")
    checkMarkdownRoundTrip("1行目\n**2行目**\n3行目", name: "newlines")
    checkMarkdownRoundTrip("そのままの日本語テキスト", name: "plain text")

    let key = "selfcheck.draft"
    DraftStore.save("下書きのテスト", key: key)
    if DraftStore.load(key) != "下書きのテスト" {
      report("draft round trip")
    }
    DraftStore.clear(key)
    if DraftStore.load(key) != nil {
      report("draft clear")
    }
  }

  /// The editor parses markdown for display and writes it back; the text must
  /// survive that trip so formatting and line breaks are never quietly lost.
  private static func checkMarkdownRoundTrip(_ markdown: String, name: String) {
    let rendered = InlineMarkdownEditor.attributed(markdown)
    let restored = InlineMarkdownEditor.markdown(from: rendered)

    if restored != markdown {
      report("markdown \(name): \(markdown.debugDescription) → \(restored.debugDescription)")
    }
  }

  private static func report(_ name: String) {
    print("SelfCheck failed — \(name)")
  }
}
#endif
