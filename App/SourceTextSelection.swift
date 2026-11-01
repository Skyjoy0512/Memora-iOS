import Foundation

enum SourceTextSelection {
  static func text(blocks: [ProjectSourceText], question: String, budget: Int) -> (text: String, isExcerpt: Bool) {
    let total = blocks.reduce(0) { $0 + render($1).count } + max(0, blocks.count - 1) * 2
    if total <= budget { return (blocks.map(render).joined(separator: "\n\n"), false) }
    let selection = selectedBlocks(blocks: blocks, question: question, budget: budget)
    return (selection.blocks.map(render).joined(separator: "\n\n"), selection.isExcerpt)
  }

  /// Keeps raw text and its real location together, including after truncation.
  static func selectedBlocks(blocks: [ProjectSourceText], question: String, budget: Int,
                             maximumBlocks: Int = 24, maximumBlockUTF8Bytes: Int = .max,
                             additionalCharactersPerBlock: Int = 0) -> (blocks: [ProjectSourceText], isExcerpt: Bool) {
    guard budget > 0, maximumBlocks > 0, maximumBlockUTF8Bytes > 0 else { return ([], !blocks.isEmpty) }
    let overhead = max(0, additionalCharactersPerBlock)
    let normalized = blocks.map { block in
      ProjectSourceText(text: block.text, page: block.page.flatMap { $0 > 0 ? $0 : nil },
        time: block.time.flatMap { $0.isFinite && $0 >= 0 && $0 <= 7 * 24 * 60 * 60 ? $0 : nil })
    }
    let total = normalized.reduce(0) { $0 + render($1).count + overhead } + max(0, normalized.count - 1) * 2
    if total <= budget, normalized.count <= maximumBlocks,
       normalized.allSatisfy({ $0.text.utf8.count <= maximumBlockUTF8Bytes }) { return (normalized, false) }
    let terms = ProjectContextBuilder.queryGrams(question)
    var ranked = normalized.enumerated().map { index, block in
      (index: index, block: block, score: ProjectContextBuilder.grams(block.text).intersection(terms).count)
    }
    ranked.sort { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }
    if (ranked.first?.score ?? 0) == 0 {
      // A broad question gets excerpts spread across the document, rather
      // than a prefix that silently excludes every later page.
      let slots = min(normalized.count, maximumBlocks, max(1, budget / 1_300))
      ranked = (0..<slots).map { slot in
        let index = slots == 1 ? 0 : slot * (normalized.count - 1) / (slots - 1)
        return (index, normalized[index], 0)
      }
    }
    var selected: [(Int, ProjectSourceText)] = [], used = 0
    for item in ranked {
      let separator = selected.isEmpty ? 0 : 2
      let locationCount = render(.init(text: "", page: item.block.page, time: item.block.time)).count
      let available = budget - used - separator - locationCount - overhead
      guard available > 0 else { continue }
      let excerpt = utf8Prefix(String(item.block.text.prefix(available)), maximumBytes: maximumBlockUTF8Bytes)
      guard !excerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
      let block = ProjectSourceText(text: excerpt, page: item.block.page, time: item.block.time)
      selected.append((item.index, block)); used += render(block).count + separator + overhead
      if selected.count >= maximumBlocks { break }
    }
    return (selected.sorted { $0.0 < $1.0 }.map(\.1), true)
  }

  private static func render(_ block: ProjectSourceText) -> String {
    let safeTime = block.time.flatMap { $0.isFinite && $0 >= 0 && $0 <= 7 * 24 * 60 * 60 ? $0 : nil }
    let location = block.page.map { "[ページ\($0)] " } ?? safeTime.map { "[\(Int($0))秒] " } ?? ""
    return location + block.text
  }

  private static func utf8Prefix(_ text: String, maximumBytes: Int) -> String {
    guard text.utf8.count > maximumBytes else { return text }
    var bytes = 0
    return String(text.prefix { character in
      let added = String(character).utf8.count
      guard added <= maximumBytes - bytes else { return false }
      bytes += added
      return true
    })
  }
}
