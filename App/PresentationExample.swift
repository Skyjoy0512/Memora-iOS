import Foundation

#if DEBUG
/// Explicitly fictional, never saved or used as a generation fallback.
enum PresentationExample {
  static func slide(_ layout: SlideArchetype) -> DocumentSlide {
    var c = SlideContent(layout: layout, subtitle: "確認した事実から次の判断へ")
    c.sources = [.init(title: "架空データ・表示検証用", locator: "ローカルfixture。実際の業績ではありません。")]
    switch layout.input {
    case .title: break
    case .items:
      let count = layout == .b08 ? 4 : layout == .b20 ? 2 : 3
      c.items = (1...count).map { .init(heading: "確認事項\($0)", body: "担当と期限を確認") }
    case .table:
      c.table = .init(columns: ["施策", "現状", "目標"], rows: [["検索", "導入中", "評価"], ["共有", "検討中", "試行"], ["資料", "開発中", "検査"]],
        scores: [[0, 0.5, 1], [0, 0.25, 0.75], [0, 0.75, 1]], rowGroups: ["製品", "製品", "運用"])
    case .metrics:
      let count = layout == .m04 ? 6 : 2
      c.metrics = (1...count).map { .init(label: "指標\($0)", value: Double($0 * 15), unit: "%", detail: "架空の比較値") }
    case .chart:
      c.chart = .init(kind: .bar, categories: ["第1期", "第2期", "第3期"],
        series: [.init(name: "実績", values: [20, 30, 40])], xLabel: "期間", yLabel: "売上", unit: "万円")
      if [.b18, .m15].contains(layout) {
        c.chart?.kind = .scatter
        c.chart?.points = [.init(label: "検索", x: 0.2, y: 0.3), .init(label: "資料", x: 0.7, y: 0.8)]
      }
      if [.m06, .b24, .m09].contains(layout) {
        c.chart?.series.append(.init(name: "計画", values: [30, 35, 45]))
      }
      if [.b23, .m07, .m08].contains(layout) {
        c.chart?.kind = .waterfall
        c.chart?.series = [.init(name: "増減", values: [100, 20, -10, 110])]
        c.chart?.categories = ["起点", "増加", "減少", "着地"]
        c.chart?.totalIndices = [0, 3]
      }
      if [.b11, .b17, .b18, .b24, .m05].contains(layout) { c.annotations = ["出典と比較条件を確認"] }
    case .diagram:
      c.diagram = .init(nodes: [.init(id: "root", label: "検討する課題", level: 0), .init(id: "a", label: "品質の確認", level: 1),
        .init(id: "b", label: "運用の確認", level: 1), .init(id: "c", label: "試行の結果", level: 2)],
        edges: [.init(from: "root", to: "a"), .init(from: "root", to: "b"), .init(from: "a", to: "c")])
    case .schedule:
      c.schedule = .init(periods: ["準備", "試行", "評価"], entries: [
        .init(label: "準備", lane: "企画", start: 0, end: 0),
        .init(label: "試行", lane: "開発", start: 1, end: 1),
        .init(label: "評価", lane: "運用", start: 2, end: 2)])
    }
    return DocumentSlide(title: "記録を整理し、判断につなげる", bullets: [], notes: "架空の表示検証です。", composition: c)
  }
}
#endif
