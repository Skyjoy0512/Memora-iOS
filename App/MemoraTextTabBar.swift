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
  @Environment(\.dynamicTypeSize) private var typeSize
  @Namespace private var selectionNamespace

  var body: some View {
    if typeSize.isAccessibilitySize {
      Picker(selection: $selection) {
        ForEach(items, id: \.self) { item in Text(title(item)).tag(item) }
      } label: {
        Text(title(selection))
          .font(MemoraTypography.body.weight(.semibold))
          .fixedSize(horizontal: false, vertical: true)
      }
      .pickerStyle(.menu)
      .tint(MemoraPalette.textPrimary)
      .frame(maxWidth: .infinity, minHeight: MemoraSpacing.touchTarget, alignment: .leading)
      .padding(.horizontal, horizontalPadding)
      .accessibilityLabel("表示する項目")
      .accessibilityValue(title(selection))
    } else {
      ScrollViewReader { proxy in
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
              .buttonStyle(MemoraQuietButtonStyle())
              .id(item)
              .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
          }
          .padding(.horizontal, horizontalPadding)
        }
        .scrollIndicators(.hidden)
        .onChange(of: selection, initial: true) { _, value in
          proxy.scrollTo(value, anchor: .center)
        }
      }
    }
  }
}
