import SwiftUI

/// The project list's quiet text filters, matching the workspace tabs: no outer
/// track, a soft capsule only under the current choice.
struct ProjectListFilterBar: View {
  @Binding var selection: ProjectListFilter
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selectionNamespace

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 4) {
        ForEach(ProjectListFilter.allCases) { filter in
          Button {
            guard selection != filter else { return }
            InteractionFeedback.shared.send(.selection)
            withAnimation(reduceMotion ? nil : MemoraMotion.control) {
              selection = filter
            }
          } label: {
            Text(filter.title)
              .font(.subheadline.weight(selection == filter ? .semibold : .regular))
              .foregroundStyle(selection == filter ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
              .lineLimit(1)
              .fixedSize(horizontal: true, vertical: false)
              .padding(.horizontal, 16)
              .frame(minHeight: 44)
              .background {
                if selection == filter {
                  Capsule()
                    .fill(Color.primary.opacity(0.06))
                    .matchedGeometryEffect(id: "projectFilterSelection", in: selectionNamespace)
                }
              }
              .contentShape(Capsule())
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(selection == filter ? .isSelected : [])
        }
      }
    }
    .scrollIndicators(.hidden)
  }
}
