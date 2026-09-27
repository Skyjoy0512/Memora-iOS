import Foundation

/// Caches where each identifiable element sits, so looking one up by id stays
/// cheap even as the array grows. The owner invalidates it when the array is
/// replaced, and the index rebuilds itself on the next lookup.
struct IdentifiableIndex<Element: Identifiable> {
  private var positions: [Element.ID: Int] = [:]
  private var isStale = true

  mutating func invalidate() {
    isStale = true
  }

  mutating func element(_ id: Element.ID, in elements: [Element]) -> Element? {
    guard let index = index(of: id, in: elements) else { return nil }
    return elements[index]
  }

  mutating func index(of id: Element.ID, in elements: [Element]) -> Int? {
    if isStale {
      // A duplicated id (from an old backup, say) keeps its first position, the
      // one `firstIndex(where:)` would find, instead of trapping.
      positions = Dictionary(
        elements.enumerated().map { ($0.element.id, $0.offset) },
        uniquingKeysWith: { first, _ in first }
      )
      isStale = false
    }

    // Stored positions can go stale if the array changed without invalidating;
    // the id check keeps a wrong hit from being returned.
    guard let index = positions[id],
          elements.indices.contains(index),
          elements[index].id == id else {
      return nil
    }
    return index
  }
}
