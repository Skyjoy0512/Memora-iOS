import SwiftUI

/// Content-level tabs shared by the Library, project list and workspace. There
/// is no outer track: only the current choice gets a soft capsule, so the row
/// reads as content rather than a second navigation bar.
struct MemoraTextTabBar<Item: Hashable>: View {
  var items: [Item]
  @Binding var selection: Item
  var horizontalPadding: CGFloat = MemoraSpacing.screen
  var title: (Item) -> String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selectionNamespace

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: MemoraSpacing.xs) {
        ForEach(items, id: \.self) { item in
          Button {
            guard selection != item else { return }
            InteractionFeedback.shared.send(.selection)
            withAnimation(reduceMotion ? nil : MemoraMotion.control) {
              selection = item
            }
          } label: {
            Text(title(item))
              .font(MemoraTypography.body.weight(selection == item ? .semibold : .regular))
              .foregroundStyle(selection == item ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
              .lineLimit(1)
              .fixedSize(horizontal: true, vertical: false)
              .padding(.horizontal, MemoraSpacing.lg)
              .frame(minHeight: MemoraSpacing.touchTarget)
              .background {
                if selection == item {
                  Capsule()
                    .fill(MemoraPalette.selection)
                    .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                }
              }
              .contentShape(Capsule())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(selection == item ? .isSelected : [])
        }
      }
      .padding(.horizontal, horizontalPadding)
    }
    .scrollIndicators(.hidden)
  }
}
