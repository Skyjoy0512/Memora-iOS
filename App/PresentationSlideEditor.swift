import SwiftUI

struct PresentationSlideEditor: View {
  @Binding var slide: DocumentSlide
  @State private var dataJSON = ""
  @State private var dataError: String?
  @State private var showsData = false

  var body: some View {
    let issues = PresentationValidator.issues(for: slide)
    Form {
      Section {
        SlideView(page: SlidePageLayout.pages(for: slide)[0])
          .listRowInsets(EdgeInsets())
      }
      Section("タイトル") { TextField("この1枚で伝えること", text: $slide.title, axis: .vertical) }
      if let content = slide.composition {
        Section("レイアウト") {
          Picker("レイアウト", selection: layoutBinding) {
            ForEach(SlideArchetype.allCases) { layout in
              Text("\(layout.rawValue) \(layout.title)").tag(layout)
            }
          }
          Text("必要データ: \(content.layout.input.rawValue)。既存のデータはレイアウトを変更しても保持します。")
            .font(.footnote).foregroundStyle(.secondary)
        }
        if let items = content.items {
          Section("本文") {
            ForEach(items) { item in
              if let index = content.items?.firstIndex(where: { $0.id == item.id }) {
                TextField("見出し", text: itemText(index, heading: true), axis: .vertical)
                TextField("本文", text: itemText(index, heading: false), axis: .vertical)
              }
            }
          }
        }
        if let metrics = content.metrics {
          Section("数値") {
            ForEach(metrics) { metric in
              if let index = metrics.firstIndex(where: { $0.id == metric.id }) {
                TextField(metric.label, value: metricValue(index), format: .number)
                  .keyboardType(.numbersAndPunctuation)
              }
            }
          }
        }
        if let table = content.table {
          Section("表") {
            ForEach(table.rows.indices, id: \.self) { row in
              DisclosureGroup("行 \(row + 1)") {
                ForEach(table.columns.indices, id: \.self) { column in
                  TextField(table.columns[column], text: tableValue(row, column), axis: .vertical)
                }
              }
            }
          }
        }
        if let chart = content.chart {
          Section("グラフのデータ") {
            ForEach(chart.series.indices, id: \.self) { series in
              DisclosureGroup(chart.series[series].name) {
                ForEach(chart.categories.indices, id: \.self) { category in
                  if chart.series[series].values.indices.contains(category) {
                    TextField(chart.categories[category], value: chartValue(series, category), format: .number)
                      .keyboardType(.numbersAndPunctuation)
                  }
                }
              }
            }
          }
        }
        Section("注記・出典") {
          TextField("注記（改行で区切る）", text: annotationBinding, axis: .vertical)
          if let sources = content.sources {
            Text(sources.map { $0.title + " " + $0.locator }.joined(separator: "\n"))
              .font(.footnote).textSelection(.enabled)
          }
        }
        Section {
          DisclosureGroup("詳細データを編集", isExpanded: $showsData) {
            Text("表の見出し、系列、座標、図の接続、期間、出典はJSONでも編集できます。適用前に検査します。")
              .font(.footnote).foregroundStyle(.secondary)
            TextEditor(text: $dataJSON).font(.body.monospaced()).frame(minHeight: 240)
              .accessibilityLabel("スライドの構造化データ")
            Button("データを適用") { applyData() }
            if let dataError { Text(dataError).foregroundStyle(MemoraPalette.danger).font(.footnote) }
          }
        }
      } else {
        Section("要点") {
          TextField("改行で要点を区切る", text: legacyBullets, axis: .vertical)
        }
      }
      Section("発表者ノート") { TextField("ノート", text: $slide.notes, axis: .vertical) }
      Section("検査") {
        if issues.isEmpty { Text("機械検査の指摘なし。事実・論理と最終描画は確認が必要です。") }
        ForEach(issues) { issue in
          Text(issue.message).foregroundStyle(issue.isError ? AnyShapeStyle(MemoraPalette.danger) : AnyShapeStyle(.secondary))
        }
      }
    }
    .navigationTitle("スライドを編集")
    .navigationBarTitleDisplayMode(.inline)
    .onChange(of: showsData) { _, open in if open { refreshData() } }
  }

  private var layoutBinding: Binding<SlideArchetype> {
    Binding(get: { slide.composition?.layout ?? .b01 }, set: { slide.composition?.layout = $0 })
  }
  private var legacyBullets: Binding<String> {
    Binding(get: { slide.bullets.joined(separator: "\n") }, set: { slide.bullets = $0.components(separatedBy: .newlines) })
  }
  private var annotationBinding: Binding<String> {
    Binding(get: { (slide.composition?.annotations ?? []).joined(separator: "\n") }, set: { slide.composition?.annotations = $0.components(separatedBy: .newlines) })
  }
  private func itemText(_ index: Int, heading: Bool) -> Binding<String> {
    Binding(get: { heading ? slide.composition?.items?[index].heading ?? "" : slide.composition?.items?[index].body ?? "" }, set: {
      if heading { slide.composition?.items?[index].heading = $0 } else { slide.composition?.items?[index].body = $0 }
    })
  }
  private func metricValue(_ index: Int) -> Binding<Double> {
    Binding(get: { slide.composition?.metrics?[index].value ?? 0 }, set: { slide.composition?.metrics?[index].value = $0 })
  }
  private func tableValue(_ row: Int, _ column: Int) -> Binding<String> {
    Binding(get: {
      guard let rows = slide.composition?.table?.rows, rows.indices.contains(row), rows[row].indices.contains(column) else { return "" }
      return rows[row][column]
    }, set: {
      guard let rows = slide.composition?.table?.rows, rows.indices.contains(row), rows[row].indices.contains(column) else { return }
      slide.composition?.table?.rows[row][column] = $0
    })
  }
  private func chartValue(_ series: Int, _ category: Int) -> Binding<Double> {
    Binding(get: { slide.composition?.chart?.series[series].values[category] ?? 0 }, set: { slide.composition?.chart?.series[series].values[category] = $0 })
  }
  private func refreshData() {
    guard let content = slide.composition else { return }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(content) { dataJSON = String(decoding: data, as: UTF8.self) }
  }
  private func applyData() {
    do {
      let updated = try PresentationToolInput.slide(["title": slide.title, "notes": slide.notes, "bullets": [String](),
        "layout": slide.composition?.layout.rawValue ?? "b01", "content_json": dataJSON])
      slide.composition = updated.composition; dataError = nil
    } catch { dataError = error.localizedDescription }
  }
}
