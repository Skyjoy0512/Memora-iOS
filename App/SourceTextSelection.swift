import Foundation

enum SourceTextSelection {
  static func text(blocks: [ProjectSourceText], question: String, budget: Int) -> (text: String, isExcerpt: Bool) {
    func render(_ block: ProjectSourceText) -> String {
      let safeTime = block.time.flatMap { $0.isFinite && $0 >= 0 && $0 < Double(Int.max) ? $0 : nil }
      let location = block.page.map { "[ページ\($0)] " } ?? safeTime.map { "[\(Int($0))秒] " } ?? ""
      return location + block.text
    }
    let total = blocks.reduce(0) { $0 + $1.text.count + 40 }
    if total <= budget { return (blocks.map(render).joined(separator: "\n\n"), false) }
    let terms = ProjectContextBuilder.queryGrams(question)
    var ranked = blocks.enumerated().map { index, block in
      (index: index, block: block, score: ProjectContextBuilder.grams(block.text).intersection(terms).count)
    }
    ranked.sort { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }
    if (ranked.first?.score ?? 0) == 0 {
      // A broad question gets excerpts spread across the document, rather
      // than a prefix that silently excludes every later page.
      let slots = min(blocks.count, max(1, budget / 1_300))
      ranked = (0..<slots).map { slot in
        let index = slots == 1 ? 0 : slot * (blocks.count - 1) / (slots - 1)
        return (index, blocks[index], 0)
      }
    }
    var selected: [(Int, String)] = [], used = 0
    for item in ranked {
      let text = render(item.block)
      let available = budget - used - 2
      guard available > 80 else { break }
      let excerpt = String(text.prefix(available))
      selected.append((item.index, excerpt)); used += excerpt.count + 2
      if selected.count >= 24 { break }
    }
    return (selected.sorted { $0.0 < $1.0 }.map(\.1).joined(separator: "\n\n"), true)
  }
}
