import Foundation

// Adapted from chatgpt-ios-ui's tableWidths, MIT, dc6e6a52.
// Copyright (c) 2026 Bryan Ramirez-Gonzalez and contributors.
// See Resources/ChatGPTUI-LICENSE.txt. No Markdown parser dependency is imported.
enum AIResponseTableLayout {
  static func widths(header: [String], rows: [[String]], availableWidth: CGFloat,
                     minimumWidth: CGFloat = 88, spacing: CGFloat = 24) -> [CGFloat] {
    guard !header.isEmpty else { return [] }
    // An unusually long cell must not make every other column unreadable.
    let weights = header.indices.map { column in
      CGFloat(max(5, min(80, ([header] + rows).map {
        column < $0.count ? $0[column].count : 0
      }.max() ?? 5)))
    }
    let total = max(1, weights.reduce(0, +))
    let viewport = availableWidth.isFinite ? max(0, availableWidth) : 0
    let contentWidth = max(0, viewport - CGFloat(header.count - 1) * spacing)
    return weights.map { max(minimumWidth, contentWidth * $0 / total) }
  }
}
