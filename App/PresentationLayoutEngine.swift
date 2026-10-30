import CoreText
import Foundation

/// Content-specific compositions share primitives, never a generic bullet fallback.
enum PresentationLayoutEngine {
  static func elements(for slide: DocumentSlide, pageNumber: Int? = nil) -> [PresentationElement] {
    guard let content = slide.composition else { return [] }
    let problems = PresentationValidator.inputIssues(for: slide)
    guard problems.isEmpty else {
      return [.init(id: 0, kind: .text, x: 54, y: 140, width: 852, height: 300,
                    text: "内容を確認してください\n" + problems.map(\.message).joined(separator: "\n"))]
    }
    var b = Builder()
    b.pageNumber = pageNumber
    let layout = content.layout
    let items = content.items ?? []
    let annotations = (content.annotations ?? []).joined(separator: "\n")
    if [.b01, .b04, .b10].contains(layout) {
      switch layout {
      case .b01:
        b.rect(54, 112, 7, 240, fill: PresentationTheme.blue)
        b.text(slide.title, 88, 140, 780, 180, size: PresentationTypography.coverTitle.size, bold: true)
        b.text(content.subtitle ?? "", 88, 342, 780, 80, size: 22)
      case .b04:
        b.rect(0, 0, 28, 540, fill: PresentationTheme.blue)
        b.text(content.subtitle ?? "", 66, 130, 810, 40, size: 20, color: PresentationTheme.blue)
        b.text(slide.title, 66, 200, 810, 200, size: PresentationTypography.sectionTitle.size, bold: true)
      default:
        b.text(slide.title, 54, 210, 852, 150, size: 38, bold: true)
        b.rule(54, 400, 852)
        b.text(content.subtitle ?? "", 54, 420, 852, 58)
      }
    } else {
      b.text(slide.title, 54, 28, 852, 80, size: 24, bold: true)
      b.rule(54, 120, 852)
      switch layout {
      case .b01, .b04, .b10: break
      case .b02:
        b.itemGrid(items, columns: 3, x: 54, y: 164, width: 852, height: 296, numbered: true)
        b.text(content.subtitle ?? "", 54, 132, 852, 28, size: 18, color: PresentationTheme.blue)
      case .b03:
        b.tocRows(items)
      case .b05:
        b.process(items, y: 194, height: 210, chevron: true)
      case .b06:
        b.paired(items, left: "前提", right: "帰結", arrow: true)
      case .b07:
        b.table(content.table, x: 54, y: 154, width: 580, height: 294, large: true)
        b.text(annotations, 668, 164, 238, 290, size: 22)
      case .b08:
        b.itemGrid(items, columns: 2, x: 54, y: 152, width: 852, height: 310)
      case .b09:
        b.table(content.table, x: 54, y: 156, width: 852, height: 304)
      case .b11:
        b.rect(54, 154, 250, 300, fill: PresentationTheme.pale)
        b.text(content.subtitle ?? annotations, 72, 174, 214, 258, size: 25, bold: true)
        b.chart(content.chart, x: 348, y: 160, width: 558, height: 292)
      case .b12:
        b.table(content.table, x: 54, y: 156, width: 852, height: 304, highlightLast: true)
      case .b13:
        b.table(content.table, x: 54, y: 156, width: 610, height: 300, visual: .heat)
        b.text(annotations, 696, 170, 210, 280)
      case .b14:
        b.table(content.table, x: 54, y: 156, width: 852, height: 304, visual: .harvey)
      case .b15:
        b.dots(content.metrics ?? [])
      case .b16:
        b.table(content.table, x: 54, y: 156, width: 852, height: 304, visual: .bubble)
      case .b17:
        b.chart(content.chart, x: 54, y: 160, width: 608, height: 292, override: .bar, horizontal: true)
        b.text(annotations, 700, 170, 206, 280)
      case .b18:
        b.chart(content.chart, x: 54, y: 160, width: 620, height: 292, override: .scatter)
        b.text(annotations, 708, 168, 198, 282)
      case .b19:
        b.pillars(items, foundation: content.subtitle ?? "", recommendation: false)
      case .b20:
        b.opposing(items)
      case .b21:
        b.itemGrid(items, columns: 3, x: 54, y: 154, width: 852, height: 300, numbered: true)
      case .b22:
        b.circles(content.metrics ?? [])
      case .b23:
        b.chart(content.chart, x: 54, y: 158, width: 852, height: 302, override: .waterfall)
      case .b24:
        b.chart(content.chart, x: 54, y: 160, width: 650, height: 292, override: .line)
        b.text(annotations, 738, 170, 168, 278, size: 20, bold: true, color: PresentationTheme.blue)
      case .b25:
        b.text(content.subtitle ?? "", 54, 154, 250, 280, size: 24, bold: true)
        b.itemRows(items, x: 344, y: 154, width: 562, height: 300)
      case .b26:
        b.paired(items, left: "課題", right: "打ち手", arrow: false)
      case .b27:
        b.rect(54, 156, 260, 300, fill: PresentationTheme.pale)
        b.text(content.subtitle ?? slide.title, 74, 176, 220, 250, size: 26, bold: true)
        b.itemRows(items, x: 352, y: 160, width: 554, height: 300, numbered: true)
      case .b28:
        b.schedule(content.schedule, mode: .swimlane)
      case .b29:
        b.twoTier(items)
      case .b30:
        b.qa(items)
      case .m01:
        b.text(content.subtitle ?? "", 54, 150, 220, 300, size: 25, bold: true, color: PresentationTheme.blue)
        b.itemRows(items, x: 316, y: 152, width: 590, height: 304, numbered: true)
      case .m02:
        b.evidenceRows(items, lead: content.subtitle ?? "")
      case .m03:
        b.bigStats(content.metrics ?? [])
      case .m04:
        b.kpiTiles(content.metrics ?? [])
      case .m05:
        b.chart(content.chart, x: 54, y: 156, width: 620, height: 298)
        b.rule(700, 158, 206)
        b.text(annotations, 710, 180, 196, 270, size: 22)
      case .m06:
        b.chart(content.chart, x: 54, y: 154, width: 852, height: 306, override: .stacked)
      case .m07:
        b.chart(content.chart, x: 54, y: 196, width: 852, height: 256, override: .waterfall)
        b.text(content.subtitle ?? "", 54, 132, 852, 34, size: 18)
      case .m08:
        b.chart(content.chart, x: 54, y: 156, width: 852, height: 304, override: .waterfall, connectors: true)
      case .m09:
        if let chart = content.chart {
          let count = max(1, chart.series.count)
          let w = (852 - Double(count - 1) * 24) / Double(count)
          for (i, series) in chart.series.enumerated() {
            var small = chart; small.series = [series]
            b.text(series.name, 54 + Double(i) * (w + 24), 148, w, 30, size: 20, bold: true)
            b.chart(small, x: 54 + Double(i) * (w + 24), y: 192, width: w, height: 250,
                    sharedRange: chart.series.flatMap(\.values))
          }
        }
      case .m10:
        b.table(content.table, x: 54, y: 156, width: 852, height: 304, highlightLast: true)
        b.rect(54, 148, 852, 3, fill: PresentationTheme.blue)
      case .m11:
        b.table(content.table, x: 54, y: 178, width: 852, height: 282, large: true)
        b.text(content.subtitle ?? "", 54, 140, 852, 30, size: 18)
      case .m12:
        b.table(content.table, x: 54, y: 154, width: 852, height: 306, visual: .heat, highlightLast: true)
      case .m13:
        b.table(content.table, x: 54, y: 154, width: 852, height: 306, visual: .harvey)
      case .m14:
        b.table(content.table, x: 54, y: 154, width: 852, height: 306, visual: .heat)
      case .m15:
        b.matrix(content.chart)
      case .m16:
        b.table(content.table, x: 54, y: 170, width: 852, height: 290, highlightLast: true)
        b.text(content.subtitle ?? "", 54, 134, 852, 30, size: 18, color: PresentationTheme.blue)
      case .m17:
        b.table(content.table, x: 54, y: 154, width: 852, height: 306, nested: true)
      case .m18:
        b.table(content.table, x: 54, y: 166, width: 852, height: 294)
        b.line(54, 148, 906, 148, color: PresentationTheme.blue)
      case .m19:
        b.itemGrid(items, columns: 3, x: 54, y: 154, width: 852, height: 300)
      case .m20:
        b.pillars(items, foundation: content.subtitle ?? "", recommendation: true)
      case .m21:
        b.imperatives(items)
      case .m22:
        b.itemGrid(items, columns: 3, x: 54, y: 166, width: 852, height: 288, numbered: true)
      case .m23:
        b.paired(items, left: "課題", right: "対応する施策", arrow: true)
      case .m24:
        b.process(items, y: 180, height: 260, chevron: false)
      case .m25:
        b.diagram(content.diagram, fork: false)
      case .m26:
        b.paired(items, left: "現状", right: "目指す姿", arrow: true)
      case .m27:
        b.process(items, y: 206, height: 172, chevron: false, calculation: true)
      case .m28:
        b.process(items, y: 164, height: 280, chevron: false)
      case .m29:
        b.cycle(items)
      case .m30:
        b.process(items, y: 154, height: 298, chevron: true)
      case .m31:
        b.process(items, y: 240, height: 170, chevron: true)
        b.text(content.subtitle ?? "", 54, 156, 852, 64, size: 24, bold: true)
      case .m32:
        b.diagram(content.diagram, fork: true)
      case .m33:
        b.schedule(content.schedule, mode: .roadmap)
      case .m34:
        b.schedule(content.schedule, mode: .gantt)
      case .m35:
        b.rect(54, 154, 852, 76, fill: PresentationTheme.pale)
        b.text(content.subtitle ?? "", 72, 168, 816, 50, size: 24, bold: true)
        b.itemRows(items, x: 54, y: 254, width: 852, height: 206, numbered: true)
      }
    }
    // A cover, back cover or section divider carries no notes or source line;
    // those belong to the content pages that use the evidence.
    if layout.input != .title {
      // Every supplied annotation is retained. Side-comment layouts already position it.
      if (!([.b07, .b11, .b13, .b17, .b18, .b24, .m05] as [SlideArchetype]).contains(layout)
          || layout == .b11 && content.subtitle != nil), !annotations.isEmpty {
        b.text(annotations, 54, 466, 852, 28, size: 12, color: PresentationTheme.secondary)
      }
      let sources = (content.sources ?? []).map { "出典: \($0.title) \($0.locator)" }.joined(separator: " / ")
      b.text(sources, 54, 504, b.pageNumber == nil ? 852 : 790, 24, size: 10,
             color: PresentationTheme.secondary)
      if let pageNumber = b.pageNumber {
        b.text(String(pageNumber), 880, 506, 26, 20, size: 10, color: PresentationTheme.secondary)
      }
    }
    return b.elements
  }

  private struct Builder {
    var elements: [PresentationElement] = []
    var pageNumber: Int? = nil
    enum Visual { case plain, heat, harvey, bubble }
    enum ScheduleMode { case swimlane, roadmap, gantt }

    mutating func text(_ text: String, _ x: Double, _ y: Double, _ width: Double, _ height: Double,
                       size: Double = 20, bold: Bool = false, color: String = PresentationTheme.ink) {
      guard !text.isEmpty else { return }
      elements.append(.init(id: elements.count, kind: .text, x: x, y: y, width: width, height: height,
                            text: text, fontSize: size, bold: bold, color: color))
    }

    mutating func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double, fill: String,
                       kind: PresentationElement.Kind = .rectangle, collision: Bool = false) {
      elements.append(.init(id: elements.count, kind: kind, x: x, y: y, width: width, height: height,
                            fill: fill, checksCollision: collision))
    }

    mutating func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, color: String = PresentationTheme.rule) {
      elements.append(.init(id: elements.count, kind: .line, x: min(x1, x2), y: min(y1, y2),
                            width: abs(x2 - x1), height: abs(y2 - y1), color: color,
                            points: [.init(x: x1, y: y1), .init(x: x2, y: y2)], checksCollision: false))
    }

    mutating func rule(_ x: Double, _ y: Double, _ width: Double) { line(x, y, x + width, y) }

    mutating func polygon(_ points: [PresentationElement.Point], fill: String) {
      let xs = points.map(\.x), ys = points.map(\.y)
      let x = xs.min() ?? 0, y = ys.min() ?? 0
      elements.append(.init(id: elements.count, kind: .polygon, x: x, y: y,
                            width: (xs.max() ?? x) - x, height: (ys.max() ?? y) - y,
                            fill: fill, points: points, checksCollision: false))
    }

    mutating func itemGrid(_ items: [SlideContent.Item], columns: Int, x: Double, y: Double,
                           width: Double, height: Double, numbered: Bool = false) {
      let rows = max(1, Int(ceil(Double(items.count) / Double(columns))))
      let w = (width - Double(columns - 1) * 24) / Double(columns)
      let h = (height - Double(rows - 1) * 20) / Double(rows)
      for (i, item) in items.enumerated() {
        let left = x + Double(i % columns) * (w + 24), top = y + Double(i / columns) * (h + 20)
        rect(left, top, w, h, fill: PresentationTheme.pale)
        rect(left, top, 4, h, fill: PresentationTheme.blue)
        text((numbered ? "\(i + 1)  " : "") + item.heading, left + 16, top + 12, w - 32, 52,
             size: 22, bold: true, color: PresentationTheme.blue)
        text(item.body, left + 14, top + 76, w - 28, h - 88, size: 18)
      }
    }

    /// Jinba's table of contents: a number, the label, and its note on one
    /// line, separated by hairlines rather than cards.
    mutating func tocRows(_ items: [SlideContent.Item]) {
      let count = max(1, items.count), h = max(52.0, min(100.0, 330 / Double(count)))
      for (i, item) in items.enumerated() {
        let top = 148 + Double(i) * h
        text(String(format: "%02d", i + 1), 100, top + 8, 68, 38, size: 26, bold: true,
             color: PresentationTheme.blue)
        if h >= 70 {
          text(item.heading, 184, top + 4, 696, 34, size: 24)
          text(item.body, 184, top + 44, 696, max(16, h - 52), size: 15,
               color: PresentationTheme.secondary)
        } else {
          text(item.heading, 184, top + 8, 300, 30, size: 20)
          text(item.body, 500, top + 10, 380, 28, size: 14, color: PresentationTheme.secondary)
        }
        rule(100, top + h - 6, 780)
      }
    }

    /// Jinba's evidence basis: a short leading note on the left and large
    /// value-led rows on the right, separated by hairlines rather than cards.
    mutating func evidenceRows(_ items: [SlideContent.Item], lead: String) {
      if !lead.isEmpty {
        text(lead, 54, 166, 260, 250, size: 17, color: PresentationTheme.secondary)
      }
      let count = max(1, items.count), h = 300 / Double(count)
      for (i, item) in items.enumerated() {
        let top = 154 + Double(i) * h
        text(item.heading, 356, top + 10, 190, h - 20, size: 27, bold: true, color: PresentationTheme.blue)
        text(item.body, 560, top + 14, 346, h - 24, size: 17)
        rule(356, top + h - 2, 550)
      }
    }

    /// Numbered imperatives follow Jinba's part 21: a large blue number, a
    /// hairline, then the heading and copy in equal columns without cards.
    mutating func imperatives(_ items: [SlideContent.Item]) {
      let count = max(1, items.count), gap = 32.0
      let w = (852 - Double(count - 1) * gap) / Double(count)
      for (i, item) in items.enumerated() {
        let x = 54 + Double(i) * (w + gap)
        text("\(i + 1)", x, 150, w, 54, size: 40, bold: true, color: PresentationTheme.blue)
        line(x, 212, x + w, 212, color: PresentationTheme.ink)
        text(item.heading, x, 226, w, 54, size: 20, bold: true)
        text(item.body, x, 286, w, 200, size: 17)
      }
    }

    mutating func itemRows(_ items: [SlideContent.Item], x: Double, y: Double, width: Double, height: Double, numbered: Bool = false) {
      let h = height / Double(max(1, items.count))
      for (i, item) in items.enumerated() {
        let top = y + Double(i) * h
        if numbered { text(String(format: "%02d", i + 1), x, top + 4, 48, h - 8, size: 25, bold: true, color: PresentationTheme.blue) }
        let left = x + (numbered ? 64 : 0), available = width - (numbered ? 64 : 0)
        text(item.heading, left, top + 4, available * 0.36, h - 16, size: 21, bold: true)
        text(item.body, left + available * 0.4, top + 4, available * 0.6, h - 16, size: 19)
        rule(left, top + h - 8, available)
      }
    }

    mutating func paired(_ items: [SlideContent.Item], left: String, right: String, arrow: Bool) {
      text(left, 54, 144, 386, 30, size: 18, bold: true, color: PresentationTheme.secondary)
      text(right, 520, 144, 386, 30, size: 18, bold: true, color: PresentationTheme.blue)
      let h = 276 / Double(max(1, items.count))
      for (i, item) in items.enumerated() {
        let y = 186 + Double(i) * h
        rect(54, y, 386, h - 16, fill: PresentationTheme.pale)
        text(item.heading, 70, y + 12, 354, h - 40, size: 22, bold: true)
        if arrow {
          let mid = y + (h - 16) / 2
          polygon([.init(x: 454, y: mid - 11), .init(x: 454, y: mid + 11), .init(x: 480, y: mid)],
                  fill: PresentationTheme.blue)
        }
        text(item.body, 536, y + 12, 354, h - 40, size: 22)
      }
    }

    mutating func process(_ items: [SlideContent.Item], y: Double, height: Double, chevron: Bool, calculation: Bool = false) {
      let gap = 26.0, n = max(1, items.count), w = (852 - Double(n - 1) * gap) / Double(n)
      for (i, item) in items.enumerated() {
        let x = 54 + Double(i) * (w + gap)
        if chevron {
          polygon([.init(x: x, y: y), .init(x: x + w - 16, y: y), .init(x: x + w, y: y + 30),
                   .init(x: x + w - 16, y: y + 60), .init(x: x, y: y + 60), .init(x: x + 16, y: y + 30)], fill: PresentationTheme.blue)
          text("\(i + 1)", x + 24, y + 14, w - 48, 32, size: 24, bold: true, color: PresentationTheme.white)
        } else {
          rect(x, y, w, 60, fill: PresentationTheme.pale)
          text(calculation ? "=" : "\(i + 1)", x + 14, y + 14, w - 28, 32, size: 24, bold: true, color: PresentationTheme.blue)
          if i < n - 1 { text("→", x + w, y + 14, gap, 32, size: 22) }
        }
        text(item.heading, x + 4, y + 78, w - 8, 54, size: 22, bold: true)
        text(item.body, x + 4, y + 144, w - 8, height - 144, size: 18)
      }
    }

    mutating func pillars(_ items: [SlideContent.Item], foundation: String, recommendation: Bool) {
      let n = max(1, items.count), w = (852 - Double(n - 1) * 24) / Double(n)
      for (i, item) in items.enumerated() {
        let x = 54 + Double(i) * (w + 24)
        rect(x, 162, w, 230, fill: PresentationTheme.pale)
        rect(x, 162, w, 7, fill: recommendation && i == 0 ? PresentationTheme.orange : PresentationTheme.blue)
        text(item.heading, x + 16, 188, w - 32, 64, size: 24, bold: true)
        text(item.body, x + 16, 266, w - 32, 104, size: 19)
      }
      rect(54, 412, 852, 48, fill: PresentationTheme.blue)
      text(foundation, 70, 422, 820, 32, size: 20, bold: true, color: PresentationTheme.white)
    }

    mutating func opposing(_ items: [SlideContent.Item]) {
      for (i, item) in items.enumerated() {
        let y = 170 + Double(i) * 142
        polygon([.init(x: 54, y: y), .init(x: 414, y: y), .init(x: 450, y: y + 54), .init(x: 414, y: y + 108), .init(x: 54, y: y + 108)], fill: PresentationTheme.pale)
        polygon([.init(x: 906, y: y), .init(x: 546, y: y), .init(x: 510, y: y + 54), .init(x: 546, y: y + 108), .init(x: 906, y: y + 108)], fill: PresentationTheme.pale)
        text(item.heading, 70, y + 18, 320, 78, size: 24, bold: true)
        text(item.body, 568, y + 18, 318, 78, size: 22)
      }
    }

    mutating func twoTier(_ items: [SlideContent.Item]) {
      let w = (852 - Double(max(0, items.count - 1)) * 24) / Double(max(1, items.count))
      for (i, item) in items.enumerated() {
        let x = 54 + Double(i) * (w + 24)
        rect(x, 162, w, 110, fill: PresentationTheme.pale)
        text(item.heading, x + 16, 180, w - 32, 76, size: 22, bold: true)
        text("↓", x + w / 2 - 12, 286, 30, 40, size: 24, color: PresentationTheme.blue)
        rect(x, 338, w, 120, fill: PresentationTheme.pale)
        text(item.body, x + 16, 356, w - 32, 84, size: 20)
      }
    }

    mutating func qa(_ items: [SlideContent.Item]) {
      let h = 310 / Double(max(1, items.count))
      for (i, item) in items.enumerated() {
        let y = 152 + Double(i) * h
        text("Q", 54, y, 32, 36, size: 24, bold: true, color: PresentationTheme.blue)
        text(item.heading, 102, y, 286, h - 20, size: 21, bold: true)
        text("A", 416, y, 32, 36, size: 24, bold: true)
        text(item.body, 464, y, 442, h - 20, size: 20)
        rule(54, y + h - 10, 852)
      }
    }

    mutating func metrics(_ metrics: [SlideContent.Metric], columns: Int, large: Bool) {
      let rows = max(1, Int(ceil(Double(metrics.count) / Double(columns))))
      let w = (852 - Double(columns - 1) * 28) / Double(columns), h = 300 / Double(rows)
      for (i, metric) in metrics.enumerated() {
        let x = 54 + Double(i % columns) * (w + 28), y = 158 + Double(i / columns) * h
        text(metric.label, x, y, w, 40, size: 21, bold: true)
        text(SlideContent.number(metric.value) + metric.unit, x, y + 48, w, large ? 94 : 64,
             size: large ? 56 : 38, bold: true, color: i == 1 ? PresentationTheme.orange : PresentationTheme.blue)
        text(metric.detail ?? "", x, y + (large ? 162 : 114), w, max(20, h - (large ? 172 : 122)), size: 18)
      }
    }

    /// Shrinks a display value only as far as needed to fit its column; it
    /// never wraps a number into two lines.
    func fittedSize(_ text: String, width: Double, maximum: Double, minimum: Double) -> Double {
      var size = maximum
      while size > minimum {
        let probe = PresentationElement(id: 0, kind: .text, x: 0, y: 0, width: width, height: 150,
                                        text: text, fontSize: size, bold: true)
        if PresentationText.lines(probe).count == 1, PresentationText.widestLine(probe) <= width {
          return size
        }
        size -= 4
      }
      return minimum
    }

    /// Jinba's KPI dashboard: a thin ink rule, label, value and note per tile.
    mutating func kpiTiles(_ metrics: [SlideContent.Metric]) {
      guard !metrics.isEmpty else { return }
      let columns = min(3, metrics.count)
      let rows = max(1, Int(ceil(Double(metrics.count) / Double(columns))))
      let gap = 24.0
      let w = (852 - Double(columns - 1) * gap) / Double(columns)
      let h = (300 - Double(rows - 1) * 24) / Double(rows)
      for (i, metric) in metrics.enumerated() {
        let x = 54 + Double(i % columns) * (w + gap)
        let y = 154 + Double(i / columns) * (h + 24)
        rect(x, y, w, 3, fill: PresentationTheme.ink)
        text(metric.label, x, y + 14, w, 28, size: 17)
        text(SlideContent.number(metric.value) + metric.unit, x, y + 46, w, 60,
             size: 40, bold: true, color: PresentationTheme.blue)
        text(metric.detail ?? "", x, y + 112, w, max(24, h - 116), size: 15,
             color: PresentationTheme.secondary)
      }
    }

    /// Jinba's big-stat pair: two oversized values with the reading beneath,
    /// not a grid of tiles.
    mutating func bigStats(_ metrics: [SlideContent.Metric]) {
      let shown = Array(metrics.prefix(2))
      let count = max(1, shown.count), gap = 96.0
      let w = (852 - Double(count - 1) * gap) / Double(count)
      for (i, metric) in shown.enumerated() {
        let x = 54 + Double(i) * (w + gap)
        let value = SlideContent.number(metric.value) + metric.unit
        text(value, x, 148, w, 150,
             size: fittedSize(value, width: w, maximum: 104, minimum: 44), bold: true,
             color: PresentationTheme.blue)
        text(metric.label, x, 312, w, 60, size: 21)
        text(metric.detail ?? "", x, 374, w, 90, size: 15, color: PresentationTheme.secondary)
      }
    }

    mutating func circles(_ metrics: [SlideContent.Metric]) {
      let maximum = max(metrics.map(\.value).max() ?? 1, 0.000001)
      let w = 852 / Double(max(1, metrics.count))
      for (i, m) in metrics.enumerated() {
        let cx = 54 + Double(i) * w + w / 2, diameter = min(w - 30, 230) * sqrt(max(0, m.value) / maximum)
        rect(cx - diameter / 2, 300 - diameter / 2, diameter, diameter,
             fill: i == 0 ? PresentationTheme.blue : PresentationTheme.orange, kind: .ellipse)
        text(m.label, cx - w / 2 + 8, 154, w - 16, 48, size: 22, bold: true)
        text(SlideContent.number(m.value) + m.unit, cx - w / 2 + 8, 434, w - 16, 32, size: 24, bold: true)
      }
    }

    mutating func dots(_ metrics: [SlideContent.Metric]) {
      for (i, m) in metrics.enumerated() {
        let x = 54 + Double(i) * 440
        text(m.label, x, 150, 410, 40, size: 22, bold: true)
        for dot in 0..<100 {
          rect(x + Double(dot % 10) * 23, 214 + Double(dot / 10) * 23, 14, 14,
               fill: Double(dot) < m.value ? PresentationTheme.blue : PresentationTheme.rule, kind: .ellipse)
        }
        text(SlideContent.number(m.value) + m.unit, x + 258, 280, 150, 90, size: 38, bold: true)
      }
    }

    mutating func table(_ table: SlideContent.Table?, x: Double, y: Double, width: Double, height: Double,
                        visual: Visual = .plain, large: Bool = false, highlightLast: Bool = false, nested: Bool = false) {
      guard let table, !table.columns.isEmpty else { return }
      let n = table.columns.count, w = width / Double(n), h = height / Double(table.rows.count + 1)
      // Jinba's table rule: the header is larger and bold with no fill; the
      // data rows are separated by horizontal rules only.
      for (c, label) in table.columns.enumerated() {
        text(label, x + Double(c) * w + 10, y + 7, w - 20, h - 14, size: 21, bold: true,
             color: PresentationTheme.ink)
      }
      // A hairline under the header separates labels from data without boxing
      // every cell; alternating rows carry the eye across a wide table.
      rect(x, y + h - 2.5, width, 2.5, fill: PresentationTheme.blue)
      for (r, row) in table.rows.enumerated() {
        let top = y + Double(r + 1) * h
        for (c, value) in row.enumerated() {
          let left = x + Double(c) * w
          let score = table.scores.flatMap { $0.indices.contains(r) && $0[r].indices.contains(c) ? $0[r][c] : nil }
          if visual == .heat, let score {
            rect(left, top, w - 2, h - 2, fill: score >= 0.67 ? PresentationTheme.blue : score >= 0.34 ? "DBEAFE" : PresentationTheme.pale)
          }
          if (visual == .harvey || visual == .bubble), let score, c > 0 {
            let d = visual == .bubble ? 12 + 22 * sqrt(max(0, score)) : 28
            rect(left + 8, top + 9, d, d, fill: PresentationTheme.rule, kind: .ellipse)
            if visual == .harvey {
              sector(cx: left + 8 + d / 2, cy: top + 9 + d / 2, radius: d / 2, fraction: score, fill: PresentationTheme.blue)
            } else {
              rect(left + 8, top + 9, d, d, fill: PresentationTheme.blue, kind: .ellipse)
            }
            text(value, left + 48, top + 9, w - 56, h - 18, size: 17)
          } else {
            let indent = nested && c == 0 && table.rowGroups?.indices.contains(r) == true ? 14.0 : 0
            text(value, left + 10 + indent, top + 9, w - 20 - indent, h - 18,
                 size: large && c > 0 ? 26 : 18, bold: c == 0 || (highlightLast && c == n - 1),
                 color: visual == .heat && (score ?? 0) >= 0.67 ? PresentationTheme.white : highlightLast && c == n - 1 ? PresentationTheme.blue : PresentationTheme.ink)
          }
        }
        if r < table.rows.count - 1 { rule(x, top + h - 2, width) }
      }
      if nested, let groups = table.rowGroups {
        for (r, group) in groups.enumerated() where r == 0 || groups[r - 1] != group {
          line(x + 2, y + Double(r + 1) * h + 4, x + 2, y + Double(r + 2) * h - 4, color: PresentationTheme.blue)
        }
      }
    }

    mutating func sector(cx: Double, cy: Double, radius: Double, fraction: Double, fill: String, start: Double = -.pi / 2) {
      let fraction = max(0, min(1, fraction))
      guard fraction > 0 else { return }
      let count = max(2, Int(ceil(fraction * 96)))
      var points: [PresentationElement.Point] = [.init(x: cx, y: cy)]
      for i in 0...count {
        let angle = start + 2 * .pi * fraction * Double(i) / Double(count)
        points.append(.init(x: cx + cos(angle) * radius, y: cy + sin(angle) * radius))
      }
      polygon(points, fill: fill)
    }

    mutating func chart(_ chart: SlideContent.Chart?, x: Double, y: Double, width: Double, height: Double,
                        override: SlideContent.Chart.Kind? = nil, horizontal: Bool = false, connectors: Bool = false,
                        sharedRange: [Double]? = nil) {
      guard let chart else { return }
      let kind = override ?? chart.kind
      let px = x + 64, py = y + 26, pw = width - 88, ph = height - 92
      let values = sharedRange ?? chart.series.flatMap(\.values)
      var minimum = min(0, values.min() ?? 0), maximum = max(1, values.max() ?? 1)
      if kind == .stacked {
        let sums = chart.categories.indices.map { i in chart.series.reduce(0.0) { $0 + ($1.values.indices.contains(i) ? $1.values[i] : 0) } }
        maximum = max(1, sums.max() ?? 1)
      }
      var bridge: [(Double, Double)] = []
      if kind == .waterfall {
        var running = 0.0
        for (i, value) in (chart.series.first?.values ?? []).enumerated() {
          let from = (chart.totalIndices ?? [0]).contains(i) ? 0 : running
          running = (chart.totalIndices ?? [0]).contains(i) ? value : running + value
          bridge.append((from, running))
        }
        minimum = min(0, bridge.flatMap { [$0.0, $0.1] }.min() ?? 0)
        maximum = max(1, bridge.flatMap { [$0.0, $0.1] }.max() ?? 1)
      }
      let span = max(0.000001, maximum - minimum)
      func yy(_ value: Double) -> Double { py + ph - (value - minimum) / span * ph }
      if kind == .pie {
        let vals = chart.series.first?.values ?? [], sum = vals.reduce(0, +)
        guard sum > 0 else { return }
        var angle = -Double.pi / 2
        for (i, v) in vals.enumerated() {
          sector(cx: px + pw * 0.35, cy: py + ph / 2, radius: min(ph / 2, pw * 0.3),
                 fraction: v / sum, fill: PresentationTheme.series[i % 4], start: angle)
          angle += v / sum * 2 * .pi
          let label = chart.categories.indices.contains(i) ? chart.categories[i] : ""
          text(label + " " + SlideContent.number(v) + chart.unit, px + pw * 0.72, py + Double(i) * 36, pw * 0.28, 32, size: 16)
        }
        return
      }
      if kind == .scatter {
        let points = chart.points ?? []
        let minX = min(0, points.map(\.x).min() ?? 0), maxX = max(1, points.map(\.x).max() ?? 1)
        let minY = min(0, points.map(\.y).min() ?? 0), maxY = max(1, points.map(\.y).max() ?? 1)
        line(px, py, px, py + ph); line(px, py + ph, px + pw, py + ph)
        for p in points {
          let xx = px + (p.x - minX) / (maxX - minX) * (pw - 70), yy = py + ph - (p.y - minY) / (maxY - minY) * (ph - 34)
          rect(xx - 5, yy - 5, 10, 10, fill: PresentationTheme.blue, kind: .ellipse)
          text(p.label, xx + 10, yy - 12, 68, 32, size: 12)
        }
        text(chart.xLabel, px, py + ph + 18, pw, 26, size: 16)
        text(chart.yLabel + " " + chart.unit, x, y - 14, width * 0.45, 22, size: 14)
        drawLegend(chart, x: x, y: y, width: width)
        return
      }
      let n = max(1, chart.categories.count)
      if horizontal {
        let h = ph / Double(n)
        let plotX = x + 124, plotWidth = max(1, width - 212)
        let zeroX = plotX + (0 - minimum) / span * plotWidth
        line(zeroX, py, zeroX, py + ph)
        let ranked = zip(chart.categories, chart.series.first?.values ?? []).enumerated().sorted {
          $0.element.1 == $1.element.1 ? $0.offset < $1.offset : $0.element.1 > $1.element.1
        }
        for (i, entry) in ranked.enumerated() {
          let v = entry.element.1
          let top = py + Double(i) * h
          text(entry.element.0, x, top, 112, h - 4, size: 15)
          let valueX = plotX + (v - minimum) / span * plotWidth
          rect(min(zeroX, valueX), top + 4, max(1, abs(valueX - zeroX)), max(1, h - 18),
            fill: v < 0 ? PresentationTheme.orange : PresentationTheme.blue)
          text(SlideContent.number(v) + chart.unit, x + width - 80, top, 80, h - 4, size: 15)
        }
        return
      }
      line(px, py, px, py + ph); line(px, yy(0), px + pw, yy(0))
      for tick in 0...4 {
        let v = minimum + span * Double(tick) / 4, top = yy(v)
        rule(px, top, pw)
        text(SlideContent.number(v), x, top - 8, 56, 20, size: 12)
      }
      text(chart.yLabel + " " + chart.unit, x, y - 14, width * 0.45, 22, size: 14)
      drawLegend(chart, x: x, y: y, width: width)
      let step = pw / Double(n)
      for (i, label) in chart.categories.enumerated() {
        text(label, px + Double(i) * step + 2, py + ph + 12, step - 4, 30, size: 13)
      }
      if kind == .waterfall {
        for (i, pair) in bridge.enumerated() {
          let left = px + Double(i) * step + step * 0.18
          rect(left, min(yy(pair.0), yy(pair.1)), step * 0.64, max(1, abs(yy(pair.0) - yy(pair.1))),
               fill: (chart.totalIndices ?? [0]).contains(i) ? PresentationTheme.ink : pair.1 >= pair.0 ? PresentationTheme.blue : PresentationTheme.orange)
          if connectors && i < bridge.count - 1 { line(left + step * 0.64, yy(pair.1), left + step, yy(pair.1)) }
        }
      } else {
        var stacked = Array(repeating: 0.0, count: n)
        for (s, series) in chart.series.enumerated() {
          var previous: (Double, Double)?
          for (i, v) in series.values.enumerated() {
            let cx = px + (Double(i) + 0.5) * step
            let color = PresentationTheme.series[s % 4]
            if kind == .line {
              if let previous { line(previous.0, previous.1, cx, yy(v), color: color) }
              rect(cx - 3, yy(v) - 3, 6, 6, fill: color, kind: .ellipse)
              previous = (cx, yy(v))
            } else if kind == .stacked, stacked.indices.contains(i) {
              let from = stacked[i]; stacked[i] += v
              rect(cx - step * 0.3, yy(stacked[i]), step * 0.6, max(1, yy(from) - yy(stacked[i])), fill: color)
            } else {
              let w = step * 0.7 / Double(max(1, chart.series.count))
              rect(cx - step * 0.35 + Double(s) * w, min(yy(0), yy(v)), max(1, w - 2), max(1, abs(yy(v) - yy(0))), fill: color)
            }
          }
        }
      }
    }

    /// Jinba puts the legend above the chart, right aligned, so the reading
    /// order stays title → legend → plot rather than title → plot → legend.
    mutating func drawLegend(_ chart: SlideContent.Chart, x: Double, y: Double, width: Double) {
      let count = max(1, chart.series.count)
      let legendW = min(112, width * 0.5 / Double(count))
      var left = x + width - legendW * Double(count)
      if left < x + width * 0.5 { left = x + width * 0.5 }
      for (s, series) in chart.series.enumerated() {
        rect(left + Double(s) * legendW, y - 6, 8, 8, fill: PresentationTheme.series[s % 4])
        text(series.name, left + Double(s) * legendW + 12, y - 14, legendW - 14, 22,
             size: 11, color: PresentationTheme.secondary)
      }
    }

    mutating func matrix(_ chart: SlideContent.Chart?) {
      guard let chart else { return }
      rect(120, 170, 720, 254, fill: PresentationTheme.pale)
      line(480, 170, 480, 424); line(120, 297, 840, 297)
      text(chart.xLabel, 120, 434, 720, 28, size: 18)
      text(chart.yLabel, 54, 136, 852, 28, size: 18)
      for p in chart.points ?? [] {
        let x = 144 + p.x * 610, y = 390 - p.y * 188
        rect(x - 5, y - 5, 10, 10, fill: PresentationTheme.blue, kind: .ellipse)
        text(p.label, x + 12, y - 9, 104, 30, size: 14)
      }
    }

    mutating func diagram(_ diagram: SlideContent.Diagram?, fork: Bool) {
      guard let diagram else { return }
      let levels = max(1, (diagram.nodes.map(\.level).max() ?? 0) + 1)
      let w = min(230, (852 - Double(levels - 1) * 70) / Double(levels))
      var positions: [String: (Double, Double)] = [:]
      for level in 0..<levels {
        let nodes = diagram.nodes.filter { $0.level == level }, h = 300 / Double(max(1, nodes.count))
        for (i, node) in nodes.enumerated() { positions[node.id] = (54 + Double(level) * (852 - w) / Double(max(1, levels - 1)), 158 + Double(i) * h + h / 2 - 28) }
      }
      for edge in diagram.edges {
        if let from = positions[edge.from], let to = positions[edge.to] {
          line(from.0 + w, from.1 + 28, to.0, to.1 + 28, color: PresentationTheme.blue)
          if let label = edge.label { text(label, from.0 + w + 4, min(from.1, to.1) + 4, max(20, to.0 - from.0 - w - 8), 36, size: 12) }
        }
      }
      for node in diagram.nodes {
        guard let position = positions[node.id] else { continue }
        rect(position.0, position.1, w, 56, fill: fork && node.level == 0 ? "DBEAFE" : PresentationTheme.pale)
        text(node.label, position.0 + 10, position.1 + 10, w - 20, 40, size: 18, bold: node.level == 0)
      }
    }

    mutating func cycle(_ items: [SlideContent.Item]) {
      let n = max(1, items.count), radius = 130.0
      for i in items.indices {
        let angle = -Double.pi / 2 + Double(i) / Double(n) * 2 * .pi
        let next = -Double.pi / 2 + Double(i + 1) / Double(n) * 2 * .pi
        let cx = 480 + cos(angle) * radius * 2, cy = 306 + sin(angle) * radius
        let nx = 480 + cos(next) * radius * 2, ny = 306 + sin(next) * radius
        line(cx, cy, nx, ny, color: PresentationTheme.blue)
      }
      for (i, item) in items.enumerated() {
        let angle = -Double.pi / 2 + Double(i) / Double(n) * 2 * .pi
        let x = 480 + cos(angle) * radius * 2 - 108, y = 306 + sin(angle) * radius - 38
        rect(x, y, 216, 76, fill: PresentationTheme.pale)
        text("\(i + 1)  " + item.heading, x + 10, y + 8, 196, 30, size: 17, bold: true)
        text(item.body, x + 10, y + 40, 196, 30, size: 14)
      }
    }

    mutating func schedule(_ schedule: SlideContent.Schedule?, mode: ScheduleMode) {
      guard let schedule, !schedule.periods.isEmpty else { return }
      let periods = schedule.periods, lanes = schedule.entries.reduce(into: [String]()) { if !$0.contains($1.lane) { $0.append($1.lane) } }
      let rows = mode == .gantt ? schedule.entries.count : lanes.count
      let w = 654 / Double(periods.count), h = 258 / Double(max(1, rows))
      for (i, period) in periods.enumerated() {
        let x = 252 + Double(i) * w
        text(period, x + 6, 148, w - 12, 32, size: 17, bold: true)
        line(x, 188, x, 458)
      }
      for row in 0..<rows {
        let label = mode == .gantt ? schedule.entries[row].label : lanes[row]
        text(label, 54, 198 + Double(row) * h, 184, h - 8, size: 18, bold: true)
        rule(54, 190 + Double(row + 1) * h, 852)
      }
      for (i, entry) in schedule.entries.enumerated() {
        let row = mode == .gantt ? i : lanes.firstIndex(of: entry.lane) ?? 0
        let left = 252 + Double(entry.start) * w + 4, top = 198 + Double(row) * h
        let width = Double(entry.end - entry.start + 1) * w - 8
        if mode == .roadmap {
          polygon([.init(x: left, y: top), .init(x: left + width - 14, y: top), .init(x: left + width, y: top + 22), .init(x: left + width - 14, y: top + 44), .init(x: left, y: top + 44)], fill: PresentationTheme.blue)
        } else { rect(left, top, width, min(48, h - 18), fill: PresentationTheme.blue) }
        text((mode == .swimlane ? "\(i + 1) " : "") + entry.label, left + 8, top + 8, width - 16, min(32, h - 26),
             size: 16, color: PresentationTheme.white)
      }
    }
  }
}
