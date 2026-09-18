import SwiftUI

/// A large, gradient-filled gallery tile for one audio file. Tapping it opens
/// the meeting with a zoom transition.
struct MeetingCard: View {
  @Environment(\.colorScheme) private var colorScheme
  var meeting: Meeting

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      badge

      Spacer(minLength: 32)

      HStack(alignment: .bottom, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(meeting.title)
            .font(.title2.bold())
            .foregroundStyle(.primary)
            .lineLimit(2)

          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }

        Spacer(minLength: 8)

        Image(systemName: "arrow.up.right")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
          .frame(width: 38, height: 38)
          .background(.thinMaterial, in: Circle())
          .accessibilityHidden(true)
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, minHeight: 190, alignment: .leading)
    .background(gradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 26, style: .continuous)
        .stroke(.white.opacity(colorScheme == .dark ? 0.08 : 0.5), lineWidth: 0.5)
    }
    .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 18, y: 10)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(meeting.title)、\(MemoraFormat.duration(meeting.duration))、\(subtitle)")
  }

  private var badge: some View {
    HStack(spacing: 6) {
      Image(systemName: meeting.source == .recording ? "waveform" : "square.and.arrow.down")
      Text(MemoraFormat.duration(meeting.duration))
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(.primary)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(.thinMaterial, in: Capsule())
  }

  private var subtitle: String {
    switch meeting.status {
    case .ready, .partialFailure:
      meeting.summary.isEmpty ? meeting.status.shortLabel : meeting.summary
    default:
      meeting.status.shortLabel
    }
  }

  private var gradient: LinearGradient {
    LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
  }

  private var palette: [Color] {
    (colorScheme == .dark ? Self.darkPalettes : Self.lightPalettes)[paletteIndex]
  }

  /// Derived from the id's first byte so a file keeps the same tint across launches.
  private var paletteIndex: Int {
    let bytes = withUnsafeBytes(of: meeting.id.uuid) { Array($0) }
    return Int(bytes.first ?? 0) % Self.lightPalettes.count
  }

  private static let lightPalettes: [[Color]] = [
    [Color(red: 0.78, green: 0.87, blue: 1.00), Color(red: 0.90, green: 0.94, blue: 1.00), .white],
    [Color(red: 0.89, green: 0.81, blue: 1.00), Color(red: 0.95, green: 0.92, blue: 1.00), .white],
    [Color(red: 0.80, green: 0.92, blue: 0.99), Color(red: 0.92, green: 0.97, blue: 1.00), .white],
    [Color(red: 1.00, green: 0.88, blue: 0.93), Color(red: 0.99, green: 0.95, blue: 0.97), .white]
  ]

  private static let darkPalettes: [[Color]] = [
    [Color(red: 0.10, green: 0.15, blue: 0.28), Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.05, green: 0.06, blue: 0.10)],
    [Color(red: 0.18, green: 0.12, blue: 0.28), Color(red: 0.11, green: 0.08, blue: 0.18), Color(red: 0.05, green: 0.06, blue: 0.10)],
    [Color(red: 0.08, green: 0.17, blue: 0.26), Color(red: 0.07, green: 0.11, blue: 0.17), Color(red: 0.05, green: 0.06, blue: 0.10)],
    [Color(red: 0.24, green: 0.12, blue: 0.17), Color(red: 0.14, green: 0.08, blue: 0.11), Color(red: 0.05, green: 0.06, blue: 0.10)]
  ]
}
