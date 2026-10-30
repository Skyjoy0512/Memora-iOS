import AppKit
import Foundation
import PDFKit

/// Builds three realistic decks from fictional records, runs the same validator
/// and renderers as the app, and writes PPTX/PDF/PNG plus a report. The content
/// is invented; a passing run proves structure and rendering plumbing, not that
/// the deck reads well or that Office will render it identically.
@main
struct PresentationScenarioChecks {
  @MainActor static func main() throws {
    let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
      : "docs/presentation-integration/scenarios")
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    var report: [String] = [
      "# 実務シナリオ検証（架空データ）",
      "",
      "- 生成: \(Date.now.formatted(date: .numeric, time: .shortened))",
      "- すべて架空の企業・人物・数値。実在の企業や個人とは関係がない。",
      "- 検証するもの: 構造化スライド、根拠パック、入力/版面検査、PPTX/PDF/PNG生成",
      "- **検証しないもの**: 目視の美しさ、PowerPoint/Keynoteでの最終描画、実LLMの文章",
      ""
    ]
    var failures = 0
    for scenario in scenarios(base: base) {
      let issues = PresentationValidator.issues(for: scenario.document)
      let errors = issues.filter(\.isError)
      if !errors.isEmpty {
        failures += 1
        report.append("## \(scenario.name)")
        report.append("")
        report.append("**失敗**: " + errors.map { "\($0.code): \($0.message)" }.joined(separator: " / "))
        report.append("")
        
                continue
      }
      let directory = output.appendingPathComponent(scenario.id, isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let pptx = PPTXWriter.data(for: scenario.document)
      try pptx.write(to: directory.appendingPathComponent("\(scenario.id).pptx"))
      try renderPDF(scenario.document, to: directory.appendingPathComponent("\(scenario.id).pdf"),
        pngDirectory: directory)

      let evidence = scenario.document.presentationEvidence
      let current = evidence?.decisions.filter(\.isCurrent) ?? []
      report.append("## \(scenario.id) \(scenario.name)")
      report.append("")
      report.append("- スライド: \(scenario.document.slides.count)枚")
      report.append("- 使用レイアウト: " + scenario.document.slides.compactMap { $0.composition?.layout.rawValue }.joined(separator: ", "))
      if let evidence {
        report.append("- 根拠: 候補\(evidence.investigation.consideredSources) / 許可\(evidence.investigation.allowedSources) / 採用\(evidence.investigation.includedSources)")
        report.append("- 現在の決定: \(current.count)件" + (current.isEmpty ? "" : "（" + current.prefix(3).map(\.statement).joined(separator: " / ") + "）"))
        report.append("- 前回最終版: \(evidence.previousFinalDeck?.title ?? "なし")")
        report.append("- 前回からの変更: \(evidence.changesSincePreviousDeck.count)件")
        report.append("- 矛盾: \(evidence.contradictions.count)件 / 不足: \(evidence.gaps.count)件 / 未確認: \(evidence.unconfirmed.count)件")
      }
      let notes = issues.filter { !$0.isError }
      report.append("- 機械検査の注意: \(notes.count)件" + (notes.isEmpty ? "" : "（" + notes.prefix(5).map(\.message).joined(separator: " / ") + "）"))
      report.append("- 生成: `\(scenario.id)/\(scenario.id).pptx`, `.pdf`, page PNG")
      report.append("")
    }
    report.append("## 集計")
    report.append("")
    report.append("- シナリオ: \(scenarios(base: base).count)件 / 構造・版面エラー: \(failures)件")
    report.append("- 目視・Office実描画の合格: 未実施")
    try report.joined(separator: "\n").write(to: output.appendingPathComponent("SCENARIO_REPORT.md"),
      atomically: true, encoding: .utf8)
    print("PresentationScenarioChecks: \(failures == 0 ? "passed" : "failed") (\(scenarios(base: base).count) scenarios, PPTX/PDF/PNG in \(output.path))")
    if failures > 0 { exit(1) }
  }

  struct Scenario {
    var id: String
    var name: String
    var document: MemoraDocument
  }

  static func scenarios(base: Date) -> [Scenario] {
    [managementReport(base: base), salesProposal(base: base), deckUpdate(base: base)]
  }

  // MARK: - A: 経営会議向け事業報告

  static func managementReport(base: Date) -> Scenario {
    let previous = source("deck:final", .previousDeck, "前回最終版 販売システム報告",
      "第2四半期の売上は 8,200 万円。本番リリースはA案で承認済み。", base.addingTimeInterval(-90 * 86_400),
      version: "4", isFinal: true)
    let sources = [
      previous,
      source("record:01", .record, "販売システム定例 4月",
        "本番リリースをA案で決定。売上は 8,200 万円。課題は店舗展開の遅延。", base.addingTimeInterval(-80 * 86_400)),
      source("record:02", .record, "販売システム定時 5月",
        "A案をB案へ変更。定期課金の設計を優先する。売上は 8,900 万円。", base.addingTimeInterval(-50 * 86_400)),
      source("record:03", .record, "販売システム定例 6月",
        "本番移行を承認。売上は 9,600 万円。リスクは運用体制の不足。", base.addingTimeInterval(-20 * 86_400)),
      source("record:04", .record, "店舗展開会議",
        "店舗展開は撤回。EC先行へ方針を変更。", base.addingTimeInterval(-15 * 86_400)),
      source("person:01", .person, "佐藤 花子", "佐藤 花子", base)
    ]
    let decisions = [
      decision("d1", "販売システムのリリース方式", "A案でリリースする", base.addingTimeInterval(-80 * 86_400), .approved, "佐藤 花子", "record:01"),
      decision("d2", "販売システムのリリース方式", "B案へ変更する", base.addingTimeInterval(-50 * 86_400), .changed, nil, "record:02"),
      decision("d3", "店舗展開", "店舗展開を撤回する", base.addingTimeInterval(-15 * 86_400), .withdrawn, "佐藤 花子", "record:04")
    ]
    let evidence = PresentationContextBuilder.build(
      request: .init(purpose: "第3四半期の事業報告と追加投資の判断", audience: "経営会議",
        decisionRequired: "追加投資を承認するか", query: "販売システム 売上 本番移行 店舗展開",
        projectName: "販売システム刷新"),
      sources: sources, decisions: decisions, characterBudget: 20_000)
    var document = MemoraDocument(title: "販売システム 第3四半期 事業報告", kind: .slides)
    document.presentationEvidence = evidence
    document.slides = [
      cover("販売システム 第3四半期 事業報告", "追加投資の判断に向けて", "経営会議 2026年10月"),
      summary("売上は計画を上回るが、運用体制と投資対効果の確認が必要", [
        ("売上", "第2四半期 8,200万円から 9,600万円へ増加"),
        ("決定", "A案からB案へ変更し、定期課金を優先"),
        ("判断", "追加投資の範囲と運用体制を今回決める")
      ]),
      kpi("主要指標は改善、投資回収は未確定", [
        metric("売上", 9_600, "万円", "前四半期 8,200万円"),
        metric("解約率", 2.4, "%", "前四半期 3.1%"),
        metric("導入店舗", 42, "店", "計画 50店"),
        metric("投資回収", 18, "か月", "前回試算 15か月")
      ]),
      heatmap("運用体制と店舗展開に遅れが残る", columns: ["売上", "解約", "運用", "店舗"], rows: [
        ["計画", "達成", "達成", "一部遅れ"],
        ["実績", "達成", "未達", "保留"]
      ], scores: [[1, 1, 0.5, 0.6], [1, 0.3, 0.2, 0.4]]),
      waterfall("売上増は解約改善と単価上昇がけん引", categories: ["前期", "単価", "解約", "新規", "今期"],
        values: [8_200, 600, 700, 100, 9_600]),
      scr("追加投資の前に運用体制の補強が必要",
        situation: "売上は増加し、本番移行も完了した。",
        challenge: "運用担当が不足し、店舗展開は撤回された。",
        action: "運用体制へ先行投資し、店舗展開は再評価する。"),
      riskTable("投資判断に残る3つのリスク", [
        ["運用体制", "採用遅延", "外注で補完", "中"],
        ["投資回収", "試算未確定", "3か月後に再試算", "高"],
        ["店舗展開", "方針撤回", "EC先行で検証", "低"]
      ], scores: [[0.5, 0, 0.3, 0.5], [0.9, 0, 0.2, 0.9], [0.2, 0, 0.4, 0.2]]),
      decisionPage("追加投資は運用体制の補強を条件に承認する",
        subtitle: "今回決めること",
        items: [("投資額", "運用体制に 1,200万円（上限）"), ("条件", "3か月後の回収試算を再確認"), ("次回", "店舗展開はEC検証後に判断")])
    ]
    return Scenario(id: "A", name: "経営会議向け事業報告", document: document)
  }

  // MARK: - B: 営業提案

  static func salesProposal(base: Date) -> Scenario {
    let sources = [
      source("record:b1", .record, "顧客ヒアリング",
        "課題は手作業の集計。月40時間の工数。競合Aを検討中。", base.addingTimeInterval(-30 * 86_400)),
      source("record:b2", .record, "提案検討会",
        "初期費用 300万円、月額 20万円の案を比較。", base.addingTimeInterval(-10 * 86_400))
    ]
    let evidence = PresentationContextBuilder.build(
      request: .init(purpose: "顧客へ導入提案", audience: "顧客の経営層",
        decisionRequired: "導入可否", query: "手作業 集計 工数 競合 費用"),
      sources: sources, characterBudget: 12_000)
    var document = MemoraDocument(title: "集計業務の自動化 ご提案", kind: .slides)
    document.presentationEvidence = evidence
    document.slides = [
      cover("集計業務の自動化 ご提案", "月40時間を削減し、判断に時間を戻す", "2026年10月"),
      statPair("月40時間の工数と、競合比較の遅れが機会損失になっている",
        left: metric("現状工数", 40, "時間/月", "手作業の集計"),
        right: metric("削減見込み", 28, "時間/月", "自動化後")),
      currentTarget("現状の手作業を、確認と判断だけに置き換える",
        current: "担当者が転記・集計・確認を手作業で行う。",
        target: "取り込みと集計を自動化し、例外だけ確認する。"),
      optionsTable("初期費用と運用負荷のバランスでA案を推奨する", [
        ["比較軸", "A案 自動化", "B案 外注"],
        ["初期費用", "300万円", "180万円"],
        ["月額", "20万円", "35万円"],
        ["削減工数", "28時間/月", "20時間/月"],
        ["内製化", "可能", "限定的"]
      ]),
      process("導入は4週間で完了する", [
        ("要件確認", "対象業務と例外を確認"),
        ("取り込み", "既存CSVとAPIを接続"),
        ("試行", "1部門で2週間試行"),
        ("本番", "全社へ展開し運用を移管")
      ]),
      roadmap("3か月で試行、6か月で全社展開", periods: ["1か月", "2か月", "3か月", "4-6か月"],
        entries: [("要件確認", "企画", 0, 0), ("試行", "現場", 1, 2), ("全社展開", "情報システム", 3, 3)]),
      riskTable("導入時に確認する3点", [
        ["データ移行", "項目不一致", "事前マッピング", "中"],
        ["現場定着", "運用負荷", "研修と伴走", "中"],
        ["費用対効果", "削減未達", "3か月で測定", "低"]
      ], scores: [[0.5, 0, 0.3, 0.5], [0.5, 0, 0.4, 0.5], [0.3, 0, 0.2, 0.3]]),
      decisionPage("A案で4週間後に試行開始、3か月後に効果を判定する",
        subtitle: "ご判断いただきたいこと",
        items: [("方式", "A案（自動化・内製）"), ("開始", "合意後2週間以内"), ("判定", "3か月後の削減工数")])
    ]
    return Scenario(id: "B", name: "営業提案", document: document)
  }

  // MARK: - C: 既存資料の更新

  static func deckUpdate(base: Date) -> Scenario {
    let previous = source("deck:old", .previousDeck, "前回最終版 拠点統合計画",
      "拠点統合は第1案で承認。移行は2026年8月開始、費用は 4,000万円。", base.addingTimeInterval(-120 * 86_400),
      version: "2", isFinal: true)
    let sources = [
      previous,
      source("record:c1", .record, "拠点統合 定例",
        "第1案を第2案へ変更。移行開始は2026年11月。費用は 4,600万円。", base.addingTimeInterval(-20 * 86_400))
    ]
    let decisions = [
      decision("c1", "拠点統合の案", "第1案で承認", base.addingTimeInterval(-120 * 86_400), .approved, "鈴木", "deck:old"),
      decision("c2", "拠点統合の案", "第2案へ変更", base.addingTimeInterval(-20 * 86_400), .changed, "鈴木", "record:c1")
    ]
    let evidence = PresentationContextBuilder.build(
      request: .init(purpose: "前回最終版を今回の決定で更新", audience: "経営会議",
        decisionRequired: "移行開始日の変更を承認するか", query: "拠点統合 移行 費用"),
      sources: sources, decisions: decisions, characterBudget: 12_000)
    var document = MemoraDocument(title: "拠点統合計画 更新版", kind: .slides)
    document.presentationEvidence = evidence
    document.slides = [
      cover("拠点統合計画 更新版", "前回最終版からの変更点", "2026年10月"),
      evidenceBasis("前回最終版と今回の決定を突き合わせた", [
        ("前回", "第1案・2026年8月開始・4,000万円"),
        ("今回", "第2案・2026年11月開始・4,600万円"),
        ("根拠", "前回最終版と拠点統合 定例")
      ]),
      optionsTable("第2案への変更で開始は3か月後ろ倒しになる", [
        ["比較軸", "前回 第1案", "今回 第2案"],
        ["開始", "2026年8月", "2026年11月"],
        ["費用", "4,000万円", "4,600万円"],
        ["対象", "2拠点", "3拠点"],
        ["効果", "統合効果 年600万円", "年750万円"]
      ]),
      heatmap("移行準備は進むが、費用と要員に差が残る", columns: ["準備", "費用", "要員"], rows: [
        ["前回", "完了", "想定内"],
        ["今回", "進行中", "超過"]
      ], scores: [[1, 0.6, 0.8], [0.6, 0.3, 0.5]]),
      gantt("移行は11月開始、翌年3月完了へ更新", periods: ["9月", "10月", "11月", "12月", "1-3月"],
        entries: [("準備", "企画", 0, 1), ("移行", "現場", 2, 3), ("安定化", "運用", 4, 4)]),
      decisionPage("第2案と11月開始を承認し、費用超過分の扱いを決める",
        subtitle: "今回の判断",
        items: [("案", "第2案（3拠点）"), ("開始", "2026年11月"), ("費用", "4,600万円（+600万円）")])
    ]
    return Scenario(id: "C", name: "既存資料の更新", document: document)
  }

  // MARK: - Slide builders

  static func cover(_ title: String, _ subtitle: String, _ note: String) -> DocumentSlide {
    var c = SlideContent(layout: .b01, subtitle: subtitle)
    c.sources = [.init(title: "架空データ", locator: note)]
    return slide(title, c)
  }

  static func summary(_ title: String, _ items: [(String, String)]) -> DocumentSlide {
    var c = SlideContent(layout: .m01, subtitle: "要点")
    c.items = items.map { .init(heading: $0.0, body: $0.1) }
    return slide(title, c)
  }

  static func kpi(_ title: String, _ metrics: [SlideContent.Metric]) -> DocumentSlide {
    var c = SlideContent(layout: .m04)
    c.metrics = metrics
    return slide(title, c)
  }

  static func statPair(_ title: String, left: SlideContent.Metric, right: SlideContent.Metric) -> DocumentSlide {
    var c = SlideContent(layout: .m03)
    c.metrics = [left, right]
    return slide(title, c)
  }

  static func heatmap(_ title: String, columns: [String], rows: [[String]], scores: [[Double]]) -> DocumentSlide {
    var c = SlideContent(layout: .m14)
    c.table = .init(columns: columns, rows: rows, scores: scores)
    return slide(title, c)
  }

  static func waterfall(_ title: String, categories: [String], values: [Double]) -> DocumentSlide {
    var c = SlideContent(layout: .m07)
    c.chart = .init(kind: .waterfall, categories: categories,
      series: [.init(name: "売上", values: values)], xLabel: "区分", yLabel: "売上", unit: "万円")
    c.chart?.totalIndices = [0, categories.count - 1]
    return slide(title, c)
  }

  static func scr(_ title: String, situation: String, challenge: String, action: String) -> DocumentSlide {
    var c = SlideContent(layout: .m22)
    c.items = [.init(heading: "状況", body: situation),
               .init(heading: "課題", body: challenge),
               .init(heading: "打ち手", body: action)]
    return slide(title, c)
  }

  static func riskTable(_ title: String, _ rows: [[String]], scores: [[Double]]) -> DocumentSlide {
    var c = SlideContent(layout: .m12)
    c.table = .init(columns: ["リスク", "影響", "対応", "度合い"], rows: rows, scores: scores)
    return slide(title, c)
  }

  static func decisionPage(_ title: String, subtitle: String, items: [(String, String)]) -> DocumentSlide {
    var c = SlideContent(layout: .m35, subtitle: subtitle)
    c.items = items.map { .init(heading: $0.0, body: $0.1) }
    return slide(title, c)
  }

  static func currentTarget(_ title: String, current: String, target: String) -> DocumentSlide {
    var c = SlideContent(layout: .m26)
    c.items = [.init(heading: current, body: target)]
    return slide(title, c)
  }

  static func optionsTable(_ title: String, _ rows: [[String]]) -> DocumentSlide {
    var c = SlideContent(layout: .m10)
    c.table = .init(columns: rows[0], rows: Array(rows.dropFirst()))
    return slide(title, c)
  }

  static func process(_ title: String, _ items: [(String, String)]) -> DocumentSlide {
    var c = SlideContent(layout: .m28)
    c.items = items.map { .init(heading: $0.0, body: $0.1) }
    return slide(title, c)
  }

  static func roadmap(_ title: String, periods: [String], entries: [(String, String, Int, Int)]) -> DocumentSlide {
    var c = SlideContent(layout: .m33)
    c.schedule = .init(periods: periods, entries: entries.map {
      .init(label: $0.0, lane: $0.1, start: $0.2, end: $0.3)
    })
    return slide(title, c)
  }

  static func gantt(_ title: String, periods: [String], entries: [(String, String, Int, Int)]) -> DocumentSlide {
    var c = SlideContent(layout: .m34)
    c.schedule = .init(periods: periods, entries: entries.map {
      .init(label: $0.0, lane: $0.1, start: $0.2, end: $0.3)
    })
    return slide(title, c)
  }

  static func evidenceBasis(_ title: String, _ items: [(String, String)]) -> DocumentSlide {
    var c = SlideContent(layout: .m02, subtitle: "根拠の整理")
    c.items = items.map { .init(heading: $0.0, body: $0.1) }
    return slide(title, c)
  }

  static func slide(_ title: String, _ c: SlideContent) -> DocumentSlide {
    var content = c
    if content.sources == nil, content.chart != nil || content.metrics != nil || content.table != nil {
      content.sources = [.init(title: "架空データ", locator: "検証fixture。実在の業績ではありません。")]
    }
    return DocumentSlide(title: title, bullets: [], notes: "架空シナリオの検証用。実在の企業・人物ではありません。",
      composition: content)
  }

  static func metric(_ label: String, _ value: Double, _ unit: String, _ detail: String) -> SlideContent.Metric {
    .init(label: label, value: value, unit: unit, detail: detail)
  }

  static func source(_ id: String, _ kind: PresentationSourceKind, _ title: String, _ text: String,
                     _ date: Date, version: String? = nil, isFinal: Bool = false) -> PresentationEvidenceSource {
    .init(id: id, kind: kind, title: title, text: text, date: date, updatedAt: date,
      permission: .allowed, stance: .fact, confidence: .confirmed, locator: "検証fixture",
      version: version, isFinal: isFinal)
  }

  static func decision(_ id: String, _ subject: String, _ statement: String, _ date: Date,
                       _ status: DecisionStatus, _ by: String?, _ sourceID: String) -> PresentationDecisionRecord {
    .init(id: id, subject: subject, statement: statement, date: date, status: status,
      decidedBy: by, meetingTitle: nil, supersedes: nil, rationale: nil, dissent: nil,
      unresolved: nil, sourceID: sourceID)
  }

  static func renderPDF(_ document: MemoraDocument, to url: URL, pngDirectory: URL) throws {
    var box = CGRect(x: 0, y: 0, width: 960, height: 540)
    let context = CGContext(url as CFURL, mediaBox: &box, nil)!
    for slide in document.slides {
      let elements = PresentationLayoutEngine.elements(for: slide)
      context.beginPDFPage(nil)
      context.setFillColor(PresentationDrawing.color("FFFFFF")); context.fill(box)
      context.translateBy(x: 0, y: 540); context.scaleBy(x: 1, y: -1)
      PresentationDrawing.draw(elements, in: context)
      context.endPDFPage()
    }
    context.closePDF()
    guard let pdf = PDFDocument(url: url) else { return }
    for index in 0..<pdf.pageCount {
      guard let page = pdf.page(at: index) else { continue }
      let image = page.thumbnail(of: NSSize(width: 960, height: 540), for: .mediaBox)
      guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:]) else { continue }
      try png.write(to: pngDirectory.appendingPathComponent(String(format: "page-%02d.png", index + 1)))
    }
  }
}
