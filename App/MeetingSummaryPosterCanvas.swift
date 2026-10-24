import SwiftUI

struct MeetingSummaryPosterCanvas: View {
  var content: MeetingSummaryPosterContent

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack {
        Text("MEMORA / MEETING BRIEF").font(.system(size: 15, weight: .semibold, design: .monospaced))
        Spacer()
        Text(content.date).font(.system(size: 16))
      }
      .foregroundStyle(Color.black.opacity(0.6))
      Text(content.title).font(.system(size: 36, weight: .bold)).lineLimit(2)
      Rectangle().frame(height: 2)
      VStack(alignment: .leading, spacing: 12) {
        Text("要旨").font(.system(size: 17, weight: .semibold))
        Text(content.overview.isEmpty ? "概要の段落はありません。全文をご確認ください。" : content.overview)
          .font(.system(size: 25, weight: .medium)).lineSpacing(6).lineLimit(5)
      }
      HStack(alignment: .top, spacing: 28) {
        section("01 / 決定事項", items: content.decisions, lines: 5)
        Rectangle().fill(Color.black.opacity(0.15)).frame(width: 1)
        section("02 / 次のアクション", items: content.actions, lines: 5)
      }
      .frame(height: 300, alignment: .top)
      Rectangle().fill(Color.black.opacity(0.15)).frame(height: 1)
      section("03 / 未解決の確認事項", items: content.questions, lines: 2)
      Spacer(minLength: 0)
      Text("保存済み要約から抜粋。件数・長さに上限があり、長い項目は省略しています。\n記載がない欄は未抽出です。全内容・条件・出典は本文で確認してください。")
        .font(.system(size: 14)).lineSpacing(4).foregroundStyle(Color.black.opacity(0.65))
    }
    .padding(40)
    .frame(width: 720, height: 1200, alignment: .topLeading)
    .foregroundStyle(Color.black)
    .background(Color.white)
    .environment(\.layoutDirection, .leftToRight)
    .environment(\.dynamicTypeSize, .large)
    .environment(\.colorScheme, .light)
  }

  private func section(_ title: String, items: [String], lines: Int) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(title).font(.system(size: 17, weight: .semibold))
      if items.isEmpty {
        Text("要約本文からは未抽出").font(.system(size: 20)).foregroundStyle(Color.black.opacity(0.55))
      }
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        Text("• " + item).font(.system(size: 20)).lineSpacing(4).lineLimit(lines)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }
}
