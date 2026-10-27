import Foundation

/// Deterministic checks report their limits; they do not certify factual truth.
enum PresentationValidator {
  struct Issue: Hashable, Identifiable, Sendable {
    var slideID: UUID
    var code: String
    var message: String
    var isError: Bool
    var elementID: Int? = nil
    var id: String { "\(slideID):\(code):\(elementID ?? -1):\(message)" }
  }

  static func inputIssues(for slide: DocumentSlide) -> [Issue] {
    guard let c = slide.composition else { return [] }
    var issues: [Issue] = []
    func require(_ condition: Bool, _ message: String) {
      if !condition { issues.append(.init(slideID: slide.id, code: "input", message: message, isError: true)) }
    }
    require(!slide.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "主張を示すタイトルを入力してください。")
    require(slide.title.count <= 160, "タイトルが長すぎます。160文字以内にしてください。")
    require(c.readingText.reduce(0) { $0 + $1.utf8.count } <= 100_000, "1枚の情報が多すぎます。スライドを分けてください。")
    switch c.layout.input {
    case .title: break
    case .items:
      let count = c.items?.count ?? 0
      let limit: Int = switch c.layout {
      case .b08: 4
      case .b20: 2
      case .b05, .m24, .m27, .m28, .m30, .m31: 4
      case .b19, .m20, .m22: 3
      case .m29: 6
      default: 6
      }
      require((1...limit).contains(count), "\(c.layout.title)の項目は1〜\(limit)件です。")
    case .table:
      require(c.table != nil, "このレイアウトには表が必要です。")
    case .metrics:
      let count = c.metrics?.count ?? 0
      let limit = [.b15, .m03].contains(c.layout) ? 2 : c.layout == .b22 ? 3 : 6
      require((1...limit).contains(count), "数値は1〜\(limit)件で指定してください。")
    case .chart:
      require(c.chart != nil, "このレイアウトにはグラフデータが必要です。")
    case .diagram: require(c.diagram != nil, "このレイアウトにはノードと接続が必要です。")
    case .schedule: require(c.schedule != nil, "このレイアウトには期間と予定が必要です。")
    }
    if let table = c.table {
      require((2...6).contains(table.columns.count) && (1...6).contains(table.rows.count), "表は2〜6列、1〜6行です。")
      require(table.rows.allSatisfy { $0.count == table.columns.count }, "表の各行と列見出しの数が一致していません。")
      if let scores = table.scores {
        require(scores.count == table.rows.count && scores.allSatisfy { $0.count == table.columns.count }, "評価値と表の寸法を一致させてください。")
        require(scores.joined().allSatisfy { $0.isFinite && (0...1).contains($0) }, "評価値は0〜1です。")
      }
      if [.b13, .b14, .b16, .m12, .m13, .m14].contains(c.layout) {
        require(table.scores != nil, "評価・濃淡・大きさを表す数値scoresが必要です。")
      }
      if let groups = table.rowGroups { require(groups.count == table.rows.count, "行グループ数が表の行数と一致していません。") }
    }
    for metric in c.metrics ?? [] {
      require(metric.value.isFinite && abs(metric.value) <= 1e12, "数値が有限の範囲を超えています。")
      if [.b15, .b22].contains(c.layout) { require(metric.value >= 0, "割合と比例円の値は0以上にしてください。") }
      if c.layout == .b15 { require(metric.value <= 100 && metric.unit == "%", "ドットマトリクスは0〜100%を指定してください。") }
    }
    if let chart = c.chart {
      require(chart.series.count <= 4 && chart.categories.count <= 10 && (chart.points?.count ?? 0) <= 12, "グラフは4系列・10区分・12点までです。")
      require(chart.series.allSatisfy { $0.values.count == chart.categories.count }, "各系列の値の数と区分数を一致させてください。")
      require(chart.series.flatMap(\.values).allSatisfy { $0.isFinite && abs($0) <= 1e12 }, "グラフの数値が範囲外です。")
      require((chart.points ?? []).allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1e12 && abs($0.y) <= 1e12 }, "散布図の座標が範囲外です。")
      let isScatter = [.b18, .m15].contains(c.layout) || chart.kind == .scatter
      require(isScatter ? !(chart.points ?? []).isEmpty : !chart.series.isEmpty && !chart.categories.isEmpty, "グラフの値がありません。")
      if c.layout == .m15 { require((chart.points ?? []).allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) }, "2×2マトリクスの座標は0〜1で指定してください。") }
      if chart.kind == .pie || [.m06].contains(c.layout) || chart.kind == .stacked {
        require(chart.series.flatMap(\.values).allSatisfy { $0 >= 0 }, "円・積み上げは負数に対応していません。")
      }
      if chart.kind == .pie {
        require(chart.series.count == 1 && (chart.series.first?.values.reduce(0, +) ?? 0) > 0, "円グラフは合計が正の1系列です。")
      }
      if [.b23, .m07, .m08].contains(c.layout) || chart.kind == .waterfall {
        require(chart.series.count == 1, "ブリッジは1系列で指定してください。")
        require((chart.totalIndices ?? [0]).allSatisfy { chart.categories.indices.contains($0) }, "合計バーの位置が範囲外です。")
        if c.layout == .m08, let values = chart.series.first?.values, values.count >= 2,
           let totals = chart.totalIndices, totals.contains(values.count - 1) {
          var running = values[0]
          for i in 1..<(values.count - 1) { running = totals.contains(i) ? values[i] : running + values[i] }
          require(abs(running - values[values.count - 1]) <= max(1, abs(running)) * 1e-8, "増減から計算した着地と最後の合計が一致しません。")
        }
      }
      require(!chart.xLabel.isEmpty && !chart.yLabel.isEmpty, "グラフの比較軸の名前を入力してください。")
    }
    if let d = c.diagram {
      let ids = Set(d.nodes.map(\.id))
      require((1...10).contains(d.nodes.count) && d.edges.count <= 12 && ids.count == d.nodes.count, "図のノードは重複のない1〜10件、接続は12件までです。")
      require(d.nodes.allSatisfy { (0...3).contains($0.level) }, "図の階層は0〜3で指定してください。")
      require(d.edges.allSatisfy { edge in
        guard let from = d.nodes.first(where: { $0.id == edge.from }), let to = d.nodes.first(where: { $0.id == edge.to }) else { return false }
        return from.level < to.level
      }, "ツリー・分岐の接続先は次の階層の実在するノードにしてください。")
    }
    if let s = c.schedule {
      require((1...6).contains(s.periods.count) && (1...6).contains(s.entries.count), "予定は1〜6期間・1〜6件です。")
      require(s.entries.allSatisfy { $0.start >= 0 && $0.end >= $0.start && $0.end < s.periods.count }, "予定の開始・終了が期間の範囲外です。")
      if c.layout != .m34 {
        for (i, a) in s.entries.enumerated() {
          for other in s.entries.dropFirst(i + 1) where a.lane == other.lane {
            require(a.end < other.start || other.end < a.start, "同じレーンの予定が重なっています。")
          }
        }
      }
    }
    return issues
  }

  static func issues(for slide: DocumentSlide) -> [Issue] {
    var issues = inputIssues(for: slide)
    guard issues.isEmpty, let content = slide.composition else { return issues }
    let elements = PresentationLayoutEngine.elements(for: slide)
    for element in elements {
      if ![element.x, element.y, element.width, element.height].allSatisfy(\.isFinite)
          || element.x < 0 || element.y < 0 || element.width < 0 || element.height < 0
          || (element.kind != .line && (element.width == 0 || element.height == 0))
          || element.maxX > 960.01 || element.maxY > 540.01 {
        issues.append(.init(slideID: slide.id, code: "bounds", message: "要素がページの外へ出ています。", isError: true, elementID: element.id))
      }
      if element.kind == .text, Double(PresentationText.lines(element).count) * element.fontSize * 1.3 > element.height + 1 {
        issues.append(.init(slideID: slide.id, code: "overflow", message: "「\(element.text.prefix(24))」が枠に収まりません。文章を短くするか、スライドを分けてください。", isError: true, elementID: element.id))
      }
    }
    let texts = elements.filter { $0.kind == .text && $0.checksCollision }
    for (i, a) in texts.enumerated() {
      for b in texts.dropFirst(i + 1) where min(a.maxX, b.maxX) - max(a.x, b.x) > 1 && min(a.maxY, b.maxY) - max(a.y, b.y) > 1 {
        issues.append(.init(slideID: slide.id, code: "overlap", message: "テキスト枠が重なっています。", isError: true, elementID: a.id))
      }
    }
    let allText = ([slide.title] + content.readingText).joined(separator: "\n")
    if allText.range(of: #"\b(Text\s*\d+|YYYY|TODO|TBD)\b|タイトル\s*\d+|ラベル\s*\d+"#, options: .regularExpression) != nil {
      issues.append(.init(slideID: slide.id, code: "placeholder", message: "置換前のプレースホルダーが残っています。", isError: true))
    }
    if (content.sources ?? []).isEmpty, content.chart != nil || content.metrics != nil || content.table != nil {
      issues.append(.init(slideID: slide.id, code: "source", message: "数値・比較の出典がありません。原資料と照合してください。", isError: false))
    }
    for phrase in ["革命的", "圧倒的", "ゲームチェンジャー", "ご不明な点がございましたら", "さらなる高み"] where allText.contains(phrase) {
      issues.append(.init(slideID: slide.id, code: "language", message: "「\(phrase)」を具体的な事実に置き換えられるか確認してください。", isError: false))
    }
    return issues
  }

  static func issues(for document: MemoraDocument) -> [Issue] {
    var result = document.slides.flatMap { issues(for: $0) }
    var titles = Set<String>()
    for slide in document.slides where !titles.insert(slide.title).inserted {
      result.append(.init(slideID: slide.id, code: "duplicate", message: "同じ主張のスライドがあります。内容の重複を確認してください。", isError: false))
    }
    return result
  }
}
