import SwiftUI

/// The project workspace's flat segmented bar. It deliberately skips Liquid
/// Glass: the selected surface is a quiet neutral fill, as on a standard list.
struct ProjectWorkspaceTabBar: View {
  @Binding var selection: ProjectWorkspaceTab
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selectionNamespace

  var body: some View {
    HStack(spacing: 2) {
      ForEach(ProjectWorkspaceTab.allCases) { tab in
        Button {
          guard selection != tab else { return }
          InteractionFeedback.shared.send(.selection)
          withAnimation(reduceMotion ? nil : MemoraMotion.control) {
            selection = tab
          }
        } label: {
          Text(tab.title)
            .font(.subheadline.weight(selection == tab ? .semibold : .regular))
            .foregroundStyle(selection == tab ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
              if selection == tab {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                  .fill(Color(uiColor: .tertiarySystemFill))
                  .matchedGeometryEffect(id: "workspaceSelection", in: selectionNamespace)
              }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
      }
    }
    .padding(3)
    .background(Color(uiColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
