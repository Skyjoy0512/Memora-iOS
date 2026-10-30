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
    let elements = PresentationLayoutEngine.elements(for: slide, pageNumber: [.b01, .b04, .b10].contains(content.layout) ? nil : 1)
    for element in elements {
      if ![element.x, element.y, element.width, element.height].allSatisfy(\.isFinite)
          || element.x < 0 || element.y < 0 || element.width < 0 || element.height < 0
          || (element.kind != .line && (element.width == 0 || element.height == 0))
          || element.maxX > 960.01 || element.maxY > 540.01 {
        issues.append(.init(slideID: slide.id, code: "bounds", message: "要素がページの外へ出ています。", isError: true, elementID: element.id))
      }
      if element.kind == .text, Double(PresentationText.lines(element).count) * element.fontSize * 1.3 > element.height + 1
          || PresentationText.widestLine(element) > element.width + 1 {
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
    let unused: [String] = [
      content.items?.isEmpty == false && content.layout.input != .items ? "本文の項目" : nil,
      content.table != nil && content.layout.input != .table ? "表" : nil,
      content.metrics?.isEmpty == false && content.layout.input != .metrics ? "指標" : nil,
      content.chart != nil && content.layout.input != .chart ? "グラフ" : nil,
      content.diagram != nil && content.layout.input != .diagram ? "図の接続" : nil,
      content.schedule != nil && content.layout.input != .schedule ? "予定" : nil
    ].compactMap { $0 }
    if !unused.isEmpty {
      issues.append(.init(slideID: slide.id, code: "unusedContent", message: "このレイアウトでは\(unused.joined(separator: "・"))が表示されません。保存データとPPTXノートには保持します。必要な内容が見える型を選んでください。", isError: false))
    }
    if allText.range(of: #"\b(Text\s*\d+|YYYY|TODO|TBD)\b|タイトル\s*\d+|ラベル\s*\d+"#, options: .regularExpression) != nil {
      issues.append(.init(slideID: slide.id, code: "placeholder", message: "置換前のプレースホルダーが残っています。", isError: true))
    }
    if (content.sources ?? []).allSatisfy({ $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.locator.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
       content.chart != nil || content.metrics != nil || content.table != nil {
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
    result.append(contentsOf: jinbaNotes(for: document))
    var facts: [String: (Double, UUID)] = [:]
    for slide in document.slides {
      guard let c = slide.composition, let sources = c.sources, !sources.isEmpty else { continue }
      let sourceKey = sources.map { $0.title + "|" + $0.locator }.sorted().joined(separator: "\n")
      var values = (c.metrics ?? []).map { ($0.label + "|" + $0.unit, $0.value) }
      if let chart = c.chart {
        values += chart.series.flatMap { series in
          zip(chart.categories, series.values).map { (series.name + "|" + $0.0 + "|" + chart.unit, $0.1) }
        }
      }
      for (label, value) in values {
        let key = sourceKey + "|" + label
        if let previous = facts[key], previous.0.isFinite, value.isFinite,
           abs(previous.0 - value) > max(1, abs(value)) * 1e-8 {
          result.append(.init(slideID: slide.id, code: "numberConflict",
            message: "同じ出典・項目「\(label.replacingOccurrences(of: "|", with: " / "))」の数値が一致しません。時点や比較条件も確認してください。", isError: false))
        } else { facts[key] = (value, slide.id) }
      }
    }
    return result
  }

  /// Style rules from Jinba's slide-rules that can be checked without a
  /// renderer. They are notes, not a claim that the text is good.
  static func jinbaNotes(for document: MemoraDocument) -> [Issue] {
    var result: [Issue] = []
    let slides = document.slides
    if slides.count >= 4 {
      let titles = slides.map(\.title)
      let polite = titles.filter { $0.hasSuffix("です") || $0.hasSuffix("ます") || $0.hasSuffix("でした") || $0.hasSuffix("ました") }
      if polite.count * 5 >= titles.count * 3 {
        result.append(.init(slideID: slides[0].id, code: "titleStyle",
          message: "タイトルが「です・ます」で終わるページが多い。常体の主張文にしてください。", isError: false))
      }
      let patterns = Dictionary(grouping: titles) { title -> String in
        let endings = ["する", "した", "せる", "される", "になる", "とした", "へ", "を"]
        return endings.first { title.hasSuffix($0) } ?? String(title.suffix(2))
      }
      if let most = patterns.max(by: { $0.value.count < $1.value.count }), most.value.count * 5 >= titles.count * 3 {
        result.append(.init(slideID: slides[0].id, code: "titlePattern",
          message: "同じ文型で終わるタイトルが6割以上あります。事実・問い・判断をそれぞれ自然な文にしてください。", isError: false))
      }
    }
    for slide in slides {
      if ["現状と課題", "課題と対策", "本日の論点", "まとめ"].contains(where: { slide.title.hasPrefix($0 + "：") || slide.title.hasPrefix($0 + ":") }) {
        result.append(.init(slideID: slide.id, code: "titleLabel",
          message: "タイトルが分類ラベルで始まっています。何を伝えるページかを主張で書いてください。", isError: false))
      }
      guard let content = slide.composition else { continue }
      if let chart = content.chart, (chart.kind == .pie || [.b22].contains(content.layout)), chart.categories.count > 3 {
        result.append(.init(slideID: slide.id, code: "pie",
          message: "円グラフの区分が4つ以上あります。構成比は積み上げ横棒か、項目比較は横棒にしてください。", isError: false))
      }
      if let table = content.table {
        let vague = ["観点", "大項目", "その他", "項目"]
        if table.columns.contains(where: { vague.contains($0.trimmingCharacters(in: .whitespaces)) }) {
          result.append(.init(slideID: slide.id, code: "tableHeader",
            message: "表の列名「観点」「大項目」などは、下のセルを指す具体的な名詞にしてください。", isError: false))
        }
      }
      let text = ([slide.title] + content.readingText).joined(separator: "\n")
      if text.contains(" — ") || text.contains("—") {
        result.append(.init(slideID: slide.id, code: "aiSmell",
          message: "「—」による連結表現を具体的な文へ直してください。", isError: false))
      }
    }
    return result
  }
}
