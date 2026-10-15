import SwiftUI

struct ProjectSectionHeader<Actions: View>: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  var title: LocalizedStringKey
  var count: Int
  var actions: Actions

  init(_ title: LocalizedStringKey, count: Int, @ViewBuilder actions: () -> Actions) {
    self.title = title
    self.count = count
    self.actions = actions()
  }

  var body: some View {
    let layout = dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    layout {
      HStack(spacing: 6) {
        Text(title).fontWeight(.semibold)
        Text("\(count)件")
      }
      .foregroundStyle(MemoraPalette.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isHeader)
      actions.frame(minHeight: 44)
    }
    .font(.subheadline)
    .textCase(nil)
    .tint(MemoraPalette.textPrimary)
  }
}
