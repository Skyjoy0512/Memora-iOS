import SwiftUI

/// A stories-style, horizontal row of people on Home. Picking one filters the
/// timeline to their records.
struct PeopleStrip: View {
  var people: [Person]
  var selectedID: UUID?
  var onSelect: (UUID?) -> Void
  var onManage: () -> Void

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 14) {
        item(title: "すべて", symbol: .squareGrid2x2, imageData: nil, isSelected: selectedID == nil) {
          onSelect(nil)
        }

        ForEach(people) { person in
          item(
            title: person.name,
            symbol: nil,
            imageData: person.photoData,
            isSelected: selectedID == person.id
          ) {
            onSelect(selectedID == person.id ? nil : person.id)
          }
        }

        item(title: "管理", symbol: .plus, imageData: nil, isSelected: false, action: onManage)
      }
      .padding(.horizontal, MemoraSpacing.lg)
      .padding(.vertical, MemoraSpacing.xxs)
    }
    .scrollIndicators(.hidden)
  }

  private func item(
    title: String,
    symbol: MemoraIcon?,
    imageData: Data?,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    PersonBubble(
      title: title,
      symbol: symbol,
      photoData: imageData,
      isSelected: isSelected,
      onTap: action
    )
  }
}
