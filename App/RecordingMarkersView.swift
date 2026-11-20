import SwiftUI

struct RecordingMarkersView: View {
  var markers: [RecordingMarker]
  var onSeek: ((TimeInterval) -> Void)? = nil
  var onDelete: ((UUID) -> Void)? = nil

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 12) {
      Text("重要マーク \(markers.count)件")
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      ForEach(markers) { marker in
        HStack(alignment: .center, spacing: 12) {
          if let onSeek {
            Button { onSeek(marker.timestamp) } label: { markerLabel(marker) }
              .buttonStyle(.plain)
              .accessibilityLabel("\(marker.displayTitle)、\(MemoraFormat.duration(marker.timestamp))から確認")
          } else {
            markerLabel(marker)
          }
          if let onDelete {
            Button("マークを削除", icon: .trash, role: .destructive) { onDelete(marker.id) }
              .labelStyle(.iconOnly)
              .frame(width: 44, height: 44)
              .accessibilityLabel("\(MemoraFormat.duration(marker.timestamp))の重要マークを削除")
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func markerLabel(_ marker: RecordingMarker) -> some View {
    HStack(spacing: MemoraSpacing.md) {
      Image(icon: .flag).foregroundStyle(.tint)
      Text(MemoraFormat.duration(marker.timestamp)).monospacedDigit()
      Text(marker.displayTitle).frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.subheadline)
    .padding(MemoraSpacing.md)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: MemoraRadius.card))
    .contentShape(RoundedRectangle(cornerRadius: MemoraRadius.card))
  }
}
