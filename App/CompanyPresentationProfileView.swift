import SwiftUI

/// Shared with the isolated diagnostic screen; it never generates or modifies a file.
struct CompanyPresentationProfileView: View {
  var profile: CompanyPresentationProfile

  var body: some View {
    let masters = profile.masters.reduce(into: [String: CompanyPresentationProfile.Master]()) { $0[$1.id] = $1 }
    Section("PowerPointの計測") {
      LabeledContent("ページサイズ") {
        Text("\(Double(profile.widthEMU) / 12700, format: .number.precision(.fractionLength(0...1))) × \(Double(profile.heightEMU) / 12700, format: .number.precision(.fractionLength(0...1))) pt")
      }
      LabeledContent("元スライド", value: profile.slideCount.formatted())
      LabeledContent("マスター", value: profile.masters.count.formatted())
      ForEach(profile.notices, id: \.self) { notice in
        Text(notice).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }
    Section("レイアウト") {
      ForEach(profile.layouts) { layout in
        NavigationLink {
          CompanyPresentationLayoutView(layout: layout, master: masters[layout.masterPart])
        } label: {
          VStack(alignment: .leading, spacing: 4) {
            Text(layout.name)
            Text("使用 \(layout.useCount)枚 · プレースホルダー \(layout.placeholders.count)個")
              .font(.caption).foregroundStyle(.secondary)
          }
          .frame(minHeight: 44, alignment: .leading)
        }
      }
      if profile.layouts.isEmpty { Text("関連付けられたレイアウトはありません。") }
    }
  }
}
