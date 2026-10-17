import Foundation

/// Column widths for the structured ComparisonTable.
///
/// The design is independent but follows the same idea as OpenUI's
/// `ScrollableTable` (MIT, 8d9c4c3b): every column keeps one width shared by
/// its header and cells, the width grows with the content that column holds,
/// and the whole table scrolls horizontally rather than shrinking a column
/// below what large text needs. The weight is a bounded character count, so an
/// unusually long cell cannot starve the other columns.
enum AIInterfaceTableLayout {
  static func widths(header: [String], rows: [[String]], availableWidth: CGFloat,
                     minimumWidth: CGFloat = 96, spacing: CGFloat = 16) -> [CGFloat] {
    guard !header.isEmpty else { return [] }
    let weights = header.indices.map { column in
      CGFloat(max(4, min(80, ([header] + rows).map {
        column < $0.count ? $0[column].count : 0
      }.max() ?? 4)))
    }
    let total = max(1, weights.reduce(0, +))
    let viewport = availableWidth.isFinite ? max(0, availableWidth) : 0
    let contentWidth = max(0, viewport - CGFloat(header.count - 1) * spacing)
    return weights.map { max(minimumWidth, contentWidth * $0 / total) }
  }
}
