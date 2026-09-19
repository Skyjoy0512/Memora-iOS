import SwiftUI
import UIKit

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
        item(title: "すべて", symbol: "square.grid.2x2", imageData: nil, isSelected: selectedID == nil) {
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

        item(title: "管理", symbol: "plus", imageData: nil, isSelected: false, action: onManage)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 2)
    }
    .scrollIndicators(.hidden)
  }

  private func item(
    title: String,
    symbol: String?,
    imageData: Data?,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      VStack(spacing: 6) {
        ZStack {
          if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(width: 62, height: 62)
              .clipShape(Circle())
          } else {
            Circle()
              .fill(Color.primary.opacity(0.08))
              .frame(width: 62, height: 62)

            if let symbol {
              Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
            } else {
              Text(String(title.prefix(1)))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            }
          }

          Circle()
            .strokeBorder(
              isSelected ? Color.primary : Color.primary.opacity(0.12),
              lineWidth: isSelected ? 3 : 1
            )
            .frame(width: 62, height: 62)
        }

        Text(title)
          .font(.caption.weight(isSelected ? .semibold : .regular))
          .foregroundStyle(.primary)
          .lineLimit(1)
          .frame(width: 66)
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(isSelected ? "\(title)、選択中" : title)
  }
}
