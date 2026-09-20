import SwiftUI

/// A round avatar with its name below, used wherever people line up as circles:
/// the journal's people strip and the meeting detail. It shows the person's
/// photo, a symbol, or their initial.
struct PersonBubble: View {
  var title: String
  var symbol: String?
  var photoData: Data?
  var size: CGFloat = 62
  var isSelected = false
  /// When set, the bubble is a button.
  var onTap: (() -> Void)?

  var body: some View {
    if let onTap {
      Button(action: onTap) {
        content
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isSelected ? "\(title)、選択中" : title)
    } else {
      content
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
  }

  private var content: some View {
    VStack(spacing: 6) {
      ZStack {
        if let symbol {
          Circle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: size, height: size)

          Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(.secondary)
        } else {
          PersonAvatar(name: title, size: size, photoData: photoData)
        }

        Circle()
          .strokeBorder(
            isSelected ? Color.primary : Color.primary.opacity(0.12),
            lineWidth: isSelected ? 3 : 1
          )
          .frame(width: size, height: size)
      }

      Text(title)
        .font(.caption.weight(isSelected ? .semibold : .regular))
        .foregroundStyle(.primary)
        .lineLimit(1)
        .frame(width: size + 4)
    }
  }
}
