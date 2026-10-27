import Foundation

/// Source data stays separate from derived geometry; editing never round-trips through an image.
struct SlideContent: Codable, Hashable, Sendable {
  var layout: SlideArchetype
  var subtitle: String?
  var items: [Item]?
  var table: Table?
  var metrics: [Metric]?
  var chart: Chart?
  var diagram: Diagram?
  var schedule: Schedule?
  var annotations: [String]?
  var sources: [Source]?

  struct Item: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var heading: String
    var body: String
  }

  struct Table: Codable, Hashable, Sendable {
    var columns: [String]
    var rows: [[String]]
    /// Numeric scores (0...1) are supplied explicitly; text is never guessed into a score.
    var scores: [[Double]]?
    var rowGroups: [String]?
  }

  struct Metric: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var label: String
    var value: Double
    var unit: String
    var detail: String?
  }

  struct Chart: Codable, Hashable, Sendable {
    var kind: Kind
    var categories: [String]
    var series: [Series]
    var xLabel: String
    var yLabel: String
    var unit: String
    var points: [Point]?
    /// Indices of absolute bars in a bridge. Other bars are deltas.
    var totalIndices: [Int]?
    enum Kind: String, Codable, CaseIterable, Sendable { case bar, line, pie, stacked, scatter, waterfall }
    struct Series: Codable, Hashable, Sendable {
      var name: String
      var values: [Double]
    }
    struct Point: Codable, Hashable, Sendable {
      var label: String
      var x: Double
      var y: Double
      var weight: Double?
    }
  }

  struct Diagram: Codable, Hashable, Sendable {
    var nodes: [Node]
    var edges: [Edge]
    struct Node: Codable, Hashable, Sendable, Identifiable {
      var id: String
      var label: String
      var level: Int
    }
    struct Edge: Codable, Hashable, Sendable {
      var from: String
      var to: String
      var label: String?
    }
  }

  struct Schedule: Codable, Hashable, Sendable {
    var periods: [String]
    var entries: [Entry]
    struct Entry: Codable, Hashable, Sendable, Identifiable {
      var id = UUID()
      var label: String
      var lane: String
      var start: Int
      var end: Int
      var note: String?
    }
  }

  struct Source: Codable, Hashable, Sendable {
    var title: String
    var locator: String
    var excerpt: String?
  }

  var readingText: [String] {
    var text = [subtitle].compactMap { $0 }.filter { !$0.isEmpty }
    text += (items ?? []).map { $0.heading + "\n" + $0.body }
    if let table { text += [table.columns.joined(separator: " / ")] + table.rows.map { $0.joined(separator: " / ") } }
    text += (metrics ?? []).map { "\($0.label): \(Self.number($0.value))\($0.unit) \($0.detail ?? "")" }
    if let chart {
      text += [chart.xLabel + " / " + chart.yLabel + " " + chart.unit]
      text += chart.series.map { $0.name + ": " + zip(chart.categories, $0.values).map { "\($0.0) \(Self.number($0.1))" }.joined(separator: "、") }
      text += (chart.points ?? []).map { "\($0.label): x=\(Self.number($0.x)), y=\(Self.number($0.y))" }
    }
    if let diagram { text += diagram.nodes.map(\.label) + diagram.edges.map { "\($0.from) → \($0.to) \($0.label ?? "")" } }
    if let schedule { text += schedule.entries.map {
      let first = schedule.periods.indices.contains($0.start) ? schedule.periods[$0.start] : "期間外"
      let last = schedule.periods.indices.contains($0.end) ? schedule.periods[$0.end] : "期間外"
      return "\($0.lane) / \($0.label): \(first)–\(last) \($0.note ?? "")"
    } }
    text += annotations ?? []
    text += (sources ?? []).map { "出典: \($0.title) \($0.locator)" }
    return text
  }

  static func number(_ value: Double) -> String {
    value.formatted(.number.locale(Locale(identifier: "ja_JP")).precision(.fractionLength(0...4)))
  }
}
