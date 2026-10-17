import Foundation

@main
struct AIResponseTableLayoutChecks {
  static func main() {
    let standard = AIResponseTableLayout.widths(header: ["項目", "説明"], rows: [], availableWidth: 400)
    precondition(standard == [188, 188], "A short table should fill the viewport")
    let weighted = AIResponseTableLayout.widths(header: ["項目", "説明"],
      rows: [["費用", "範囲と追加費用を確認する"]], availableWidth: 400)
    precondition(weighted[1] > weighted[0], "Japanese detail needs more room than its label")
    let largeText = AIResponseTableLayout.widths(header: ["A", "B", "C", "D"], rows: [],
      availableWidth: 320, minimumWidth: 240)
    precondition(largeText.allSatisfy { $0 >= 240 } && largeText.reduce(0, +) > 320,
      "Accessibility text must scroll rather than shrink")
    for viewport: CGFloat in [0, 1, -100, .nan, .infinity] {
      let widths = AIResponseTableLayout.widths(header: ["項目", "内容", "期限"],
        rows: [["短い"], [], ["A", "B", "C", "extra ignored"]], availableWidth: viewport)
      precondition(widths.count == 3 && widths.allSatisfy { $0.isFinite && $0 >= 88 })
    }
    let extreme = AIResponseTableLayout.widths(header: ["項目", "内容"],
      rows: [["A", String(repeating: "長文", count: 10_000)]], availableWidth: 1024)
    precondition(extreme[0] >= 88 && extreme[1] < 1024)
    precondition(AIResponseTableLayout.widths(header: [], rows: [["孤立"]], availableWidth: 400).isEmpty)
    let many = AIResponseTableLayout.widths(header: Array(repeating: "列", count: 20),
      rows: Array(repeating: ["値"], count: 1000), availableWidth: 400)
    precondition(many.count == 20 && many.allSatisfy { $0 == 88 })
    print("AI response table: Japanese, large text, narrow/invalid widths, ragged/long/large tables passed")
  }
}
