import SwiftUI

/// A quiet insertion point on the journal timeline. The circle sits on the
/// same hairline as the row icons, and the whole 44pt frame is tappable.
struct JournalTimelineAddRow: View {
  var label: String
  var isLast: Bool
  var action: () -> Void = {}
  /// When present, the row opens a native menu instead of acting immediately.
  var menuActions: [JournalAddAction] = []
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .caption) private var timeWidth = 38.0

  private static let side: CGFloat = 44
  private static let lineWidth: CGFloat = 1.5
  private static let columnSpacing: CGFloat = 10

  var body: some View {
    HStack(spacing: Self.columnSpacing) {
      if !typeSize.isAccessibilitySize {
        Color.clear
          .frame(width: timeWidth, height: Self.side)
      }

      control
        .accessibilityLabel(Text(label))

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      GeometryReader { geometry in
        Rectangle()
          .fill(Color.primary.opacity(0.12))
          .frame(width: Self.lineWidth, height: isLast ? geometry.size.height / 2 : geometry.size.height)
          .offset(x: iconColumnLeading + (Self.side - Self.lineWidth) / 2, y: 0)
      }
      .accessibilityHidden(true)
    }
  }

  @ViewBuilder private var control: some View {
    if menuActions.isEmpty {
      Button(action: action) { pill }
        .buttonStyle(.plain)
    } else {
      Menu {
        ForEach(menuActions) { item in
          Button(item.title, icon: item.icon, action: item.handler)
        }
      } label: {
        pill
      }
      .buttonStyle(.plain)
    }
  }

  private var pill: some View {
    HStack(spacing: 6) {
      Image(icon: .plus, size: 12)
      Text(displayLabel)
        .font(.caption.weight(.medium))
        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
        .fixedSize(horizontal: false, vertical: true)
    }
    .foregroundStyle(MemoraPalette.textSecondary)
    .padding(.horizontal, MemoraSpacing.md)
    .padding(.vertical, MemoraSpacing.xs)
    .frame(minHeight: Self.side)
    .background(MemoraPalette.card, in: Capsule())
    .overlay {
      Capsule()
        .stroke(MemoraPalette.border.opacity(0.8), lineWidth: 0.5)
    }
    .contentShape(Capsule())
  }

  private var iconColumnLeading: CGFloat {
    typeSize.isAccessibilitySize ? 0 : timeWidth + Self.columnSpacing
  }

  /// The full sentence helps at ordinary sizes; at accessibility sizes the
  /// shorter form keeps the whole pill inside the row.
  private var displayLabel: String {
    guard typeSize.isAccessibilitySize else { return label }
    return isLast ? "記録を追加" : "この間に追加"
  }
}
