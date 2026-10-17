import Foundation

/// Resolves SourceList items against the sources the answer actually used.
///
/// Only records present in `sources` (the message's stored grounds) become
/// rows, and availability is re-decided at render time through `isAvailable`,
/// so a deleted or no-longer-permitted record shows as unavailable instead of
/// silently disappearing or staying tappable.
enum AIInterfaceSourceListModel {
  static func rows(items: [NativeAIInterface.Item], sources: [UUID: AIChatSource],
                   isAvailable: (UUID) -> Bool) -> [AIInterfaceSourceRow] {
    items.compactMap { item in
      guard let id = item.referenceID else { return nil }
      let source = sources[id]
      let title = (source?.title ?? item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty else { return nil }
      return AIInterfaceSourceRow(id: id, title: title,
        supplement: item.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
        excerptCount: source?.excerpts.count ?? 0,
        isAvailable: source != nil && isAvailable(id))
    }
  }
}
