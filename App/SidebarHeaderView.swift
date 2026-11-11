import SwiftUI

struct SidebarHeaderView: View {
  var searchDestinationTitle: String
  var onSearch: () -> Void
  var onOpenProjects: () -> Void
  var onOpenDocuments: () -> Void
  var onOpenPeople: () -> Void
  var onOpenRecorder: () -> Void
  var onOpenAccount: () -> Void
  var onOpenPlan: () -> Void

  var body: some View {
    HStack(spacing: MemoraSpacing.sm) {
      Menu {
        Section("コレクション") {
          Button("プロジェクト", icon: .rectangleStack, action: onOpenProjects)
          Button("資料", icon: .docRichtext, action: onOpenDocuments)
          Button("人物", icon: .person2, action: onOpenPeople)
        }
        Section {
          Button("外部レコーダー", icon: .dotRadiowavesLeftAndRight, action: onOpenRecorder)
          Button("アカウント", icon: .person, action: onOpenAccount)
          Button("プランと利用状況", icon: .crown, action: onOpenPlan)
        }
      } label: {
        SidebarBrandMark()
          .frame(minHeight: MemoraSpacing.touchTarget)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("Memora、その他のメニュー")
      .accessibilityHint("プロジェクト、資料、人物などを開きます")
      .accessibilityIdentifier("sidebar.more")

      Spacer(minLength: 0)

      Button {
        InteractionFeedback.shared.send(.tap)
        onSearch()
      } label: {
        Label("検索", icon: .magnifyingglass)
          .labelStyle(.iconOnly)
          .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
          .contentShape(Circle())
          .memoraGlass(in: Circle(), interactive: true)
      }
      .accessibilityHint("\(searchDestinationTitle)を検索します")
      .accessibilityIdentifier("sidebar.search")
    }
    .buttonStyle(.plain)
    .foregroundStyle(MemoraPalette.textPrimary)
    .padding(.leading, MemoraSpacing.section)
    .padding(.trailing, MemoraSpacing.screen)
    .padding(.vertical, MemoraSpacing.md)
  }
}
