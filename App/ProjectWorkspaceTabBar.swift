import SwiftUI

/// The project workspace's quiet text tabs. The chosen surface is a soft gray
/// capsule; there is no outer track, so the bar reads as content rather than a
/// control panel.
struct ProjectWorkspaceTabBar: View {
  @Binding var selection: ProjectWorkspaceTab
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selectionNamespace

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 4) {
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
              .lineLimit(1)
              .fixedSize(horizontal: true, vertical: false)
              .padding(.horizontal, 16)
              .frame(minHeight: 44)
              .background {
                if selection == tab {
                  Capsule()
                    .fill(MemoraPalette.secondaryBackground)
                    .matchedGeometryEffect(id: "workspaceSelection", in: selectionNamespace)
                }
              }
              .contentShape(Capsule())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(selection == tab ? .isSelected : [])
        }
      }
      .padding(.horizontal, 20)
    }
    .scrollIndicators(.hidden)
    .padding(.top, 2)
    .padding(.bottom, 10)
  }
}
