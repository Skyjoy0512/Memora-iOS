import SwiftUI

struct MeetingRow: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  var meeting: Meeting
  /// `List` adds its own indicator for a `NavigationLink`, so rows inside one
  /// should turn this off.
  var showsDisclosure = true
  /// A teammate's name when the record is theirs, shown under the title.
  var sharedBy: String?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      MemoraIconBadge(symbol: meeting.source.icon)

      VStack(alignment: .leading, spacing: 6) {
        let titleLayout = typeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: MemoraSpacing.xs))
          : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: MemoraSpacing.sm))
        titleLayout {
          Text(meeting.title)
            .font(MemoraTypography.body.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)

          if SampleContent.isSample(meetingID: meeting.id), !meeting.displayTitle.contains("（サンプル）") {
            SampleTag()
          }
        }

        if let sharedBy {
          SharedOwnerBadge(ownerName: sharedBy)
        }

        if showsSummary {
          Text(meeting.shortSummaryPreview)
            .font(MemoraTypography.secondary)
            .foregroundStyle(.secondary)
            .lineLimit(3)
            .lineSpacing(2)
        }

        let metadataLayout = typeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
          : AnyLayout(HStackLayout(spacing: 6))
        metadataLayout {
          Text(MemoraFormat.relativeDate(meeting.createdAt))
          if !typeSize.isAccessibilitySize { Text("·") }
          Text(MemoraFormat.duration(meeting.duration))
          if !typeSize.isAccessibilitySize { Text("·") }
          MeetingStatusLabel(status: meeting.status)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer(minLength: 8)

      if showsDisclosure {
        Image(icon: .chevronRight, size: 13)
          .foregroundStyle(.primary)
          .padding(.top, MemoraSpacing.xs)
          .accessibilityHidden(true)
      }
    }
    .padding(.vertical, MemoraSpacing.row)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }

  /// One sentence for VoiceOver instead of the pieces read in view order.
  private var accessibilityLabel: String {
    var parts = [meeting.displayTitle]
    if let sharedBy {
      parts.append("\(sharedBy)さんが共有")
    }
    if SampleContent.isSample(meetingID: meeting.id) {
      parts.append("サンプル")
    }
    if showsSummary {
      parts.append(meeting.summaryPreview)
    }
    parts.append(MemoraFormat.relativeDate(meeting.createdAt))
    parts.append(MemoraFormat.duration(meeting.duration))
    parts.append(meeting.status.shortLabel)
    return parts.joined(separator: "、")
  }

  private var showsSummary: Bool {
    switch meeting.status {
    case .ready, .partialFailure:
      return !meeting.summary.isEmpty
    default:
      return false
    }
  }
}
