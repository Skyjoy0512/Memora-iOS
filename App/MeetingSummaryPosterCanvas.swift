import SwiftUI

struct MeetingSummaryPosterCanvas: View {
  var content: MeetingSummaryPosterContent

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Text("MEMORA / SUMMARY").font(.system(size: 15, weight: .semibold, design: .monospaced))
        Spacer()
        Text(content.date).font(.system(size: 16))
      }
      .foregroundStyle(Color.black.opacity(0.6))
      Text(content.title).font(.system(size: 34, weight: .bold))
      Rectangle().frame(height: 2)
      ForEach(content.sections) { section in
        MeetingSummaryPosterSectionView(section: section)
      }
      Text(content.hasOmissions
           ? "保存済み要約の一部を掲載しています。省略した項目・条件を含む全文は要約本文で確認できます。"
           : "保存済み要約から作成。全文は要約本文で確認できます。")
        .font(.system(size: 14)).lineSpacing(4).foregroundStyle(Color.black.opacity(0.65))
    }
    .padding(36)
    .frame(width: 720, alignment: .topLeading)
    .fixedSize(horizontal: false, vertical: true)
    .foregroundStyle(Color.black)
    .background(Color.white)
    .environment(\.layoutDirection, .leftToRight)
    .environment(\.dynamicTypeSize, .large)
    .environment(\.colorScheme, .light)
  }
}
