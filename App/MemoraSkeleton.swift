import SwiftUI

/// One static, low-contrast placeholder group avoids competing shimmer layers.
struct MemoraSkeleton: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      RoundedRectangle(cornerRadius: 3).frame(height: 16)
      RoundedRectangle(cornerRadius: 3).frame(height: 16)
      RoundedRectangle(cornerRadius: 3).frame(maxWidth: 220).frame(height: 16)
    }
    .foregroundStyle(.quaternary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityHidden(true)
  }
}
