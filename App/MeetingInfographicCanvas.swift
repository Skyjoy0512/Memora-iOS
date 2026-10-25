import SwiftUI

struct MeetingInfographicCanvas: View {
  var title: String
  var date: String
  var document: MeetingInfographic

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack {
        Text("MEMORA / INSIGHT MAP").tracking(2)
        Spacer()
        Text(date)
      }.font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
      Text(title).font(.system(size: 20, weight: .medium)).foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 12) {
        Text(document.content.headline.label).font(.system(size: 16, weight: .semibold))
        Text(document.content.headline.text).font(.system(size: 40, weight: .bold)).lineSpacing(5)
          .fixedSize(horizontal: false, vertical: true)
      }.frame(maxWidth: .infinity, alignment: .leading).padding(24).background(Color(white: 0.92))
      LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 16) {
        ForEach(document.content.panels) { panel in MeetingInfographicPanelView(panel: panel) }
      }
      Text("本文に基づく整理・解釈 / \(document.modelLabel)\n条件・未確定事項は本文と根拠もご確認ください。")
        .font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
    }
    .padding(32).frame(width: 720, alignment: .leading)
    .foregroundStyle(.black).background(.white)
    .environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .large)
    .environment(\.layoutDirection, .leftToRight)
  }
}
