import SwiftUI

/// A project laid out like an iOS Home Screen folder: a rounded glass square
/// holding the latest meetings' icons, with the name and count below.
struct ProjectFolderTile: View {
  var space: MemoraSpace
  var meetingCount: Int
  var symbols: [MemoraIcon]

  var body: some View {
    VStack(spacing: 8) {
      ZStack {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .fill(.thinMaterial)
          .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
              .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
          }

        VStack(spacing: 8) {
          HStack(spacing: 8) {
            miniIcon(at: 0)
            miniIcon(at: 1)
          }
          HStack(spacing: 8) {
            miniIcon(at: 2)
            miniIcon(at: 3)
          }
        }
        .padding(16)
      }
      .aspectRatio(1, contentMode: .fit)

      VStack(spacing: 4) {
        Text(space.name)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)

        Text("\(meetingCount)件")
          .font(.caption)
          .foregroundStyle(.secondary)

        if SampleContent.isSample(spaceID: space.id) {
          SampleTag()
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    let sample = SampleContent.isSample(spaceID: space.id) ? "、サンプル" : ""
    return "\(space.name)、\(meetingCount)件の議事録\(sample)"
  }

  @ViewBuilder
  private func miniIcon(at index: Int) -> some View {
    if symbols.indices.contains(index) {
      Image(icon: symbols[index])
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    } else {
      Color.clear
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}
