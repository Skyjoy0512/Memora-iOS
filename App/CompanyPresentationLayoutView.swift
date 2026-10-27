import SwiftUI

struct CompanyPresentationLayoutView: View {
  var layout: CompanyPresentationProfile.Layout
  var master: CompanyPresentationProfile.Master?

  var body: some View {
    MemoraForm {
      Section {
        LabeledContent("種類", value: layout.kind)
        LabeledContent("使用スライド", value: layout.useCount.formatted())
        Text(layout.id).font(.caption).textSelection(.enabled)
        if let background = layout.background { LabeledContent("背景", value: background) }
        ForEach(layout.notices, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
      }
      Section("プレースホルダー") {
        ForEach(layout.placeholders) { placeholder in
          VStack(alignment: .leading, spacing: 5) {
            Text("\(placeholder.kind) · \(placeholder.index)").font(.headline)
            if let frame = placeholder.frame {
              Text("位置 \(point(frame.x)), \(point(frame.y)) pt")
              Text("サイズ \(point(frame.width)) × \(point(frame.height)) pt")
            } else { Text("位置は未確定です。") }
            if let source = placeholder.frameSource {
              Text(source == layout.id ? "位置: このレイアウト" : "位置: マスターから継承")
            }
            if let font = placeholder.font { Text("明示フォント: \(font)") }
            if let size = placeholder.fontSize { Text("文字サイズ例: \(size, format: .number) pt") }
          }
          .font(.subheadline).fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
        }
        if layout.placeholders.isEmpty { Text("プレースホルダーはありません。") }
      }
      Section {
        if let master {
          Text(master.id).font(.caption).textSelection(.enabled)
          LabeledContent("マスター図形・画像", value: master.decorations.count.formatted())
          if let theme = master.theme {
            DisclosureGroup("テーマのフォント") {
              Text("見出し: \(fontNames(theme.headingFonts))")
              Text("本文: \(fontNames(theme.bodyFonts))")
            }
            DisclosureGroup("テーマ色") {
              ForEach(theme.colors.keys.sorted(), id: \.self) { key in
                LabeledContent(key, value: "#" + (theme.colors[key] ?? ""))
              }
            }
          }
          DisclosureGroup("マスターの文字サイズ例") {
            ForEach(master.textStyles.keys.sorted(), id: \.self) { key in
              LabeledContent(key) { Text("\(master.textStyles[key] ?? 0, format: .number) pt") }
            }
          }
        }
        LabeledContent("レイアウト図形・画像", value: layout.decorations.count.formatted())
      } header: { Text("マスターと装飾") } footer: {
        Text("タイトル・本文・フッター等の位置と書式例を計測しています。余白の自動選択、表・グラフの再現、新規ページへの適用はまだ行いません。フォントのインストール状況も未検証です。")
      }
    }
    .navigationTitle(layout.name).navigationBarTitleDisplayMode(.inline)
    .tint(.primary)
  }

  private func point(_ emu: Int) -> String {
    (Double(emu) / 12700).formatted(.number.precision(.fractionLength(0...1)))
  }

  private func fontNames(_ values: [String: String]) -> String {
    values.keys.sorted().map { "\($0): \(values[$0] ?? "")" }.formatted(.list(type: .and))
  }
}
