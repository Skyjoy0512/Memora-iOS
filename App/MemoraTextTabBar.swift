import SwiftUI

/// Content-level tabs shared by the Library, project list and workspace. There
/// is no outer track: only the current choice gets a soft capsule, so the row
/// reads as content rather than a second navigation bar.
struct MemoraTextTabBar<Item: Identifiable & Equatable>: View {
  var items: [Item]
  @Binding var selection: Item
  var horizontalPadding: CGFloat = 20
  var title: (Item) -> String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selectionNamespace

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 4) {
        ForEach(items) { item in
          Button {
            guard selection != item else { return }
            InteractionFeedback.shared.send(.selection)
            withAnimation(reduceMotion ? nil : MemoraMotion.control) {
              selection = item
            }
          } label: {
            Text(title(item))
              .font(.subheadline.weight(selection == item ? .semibold : .regular))
              .foregroundStyle(selection == item ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
              .lineLimit(1)
              .fixedSize(horizontal: true, vertical: false)
              .padding(.horizontal, 16)
              .frame(minHeight: 44)
              .background {
                if selection == item {
                  Capsule()
                    .fill(Color.primary.opacity(0.06))
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
