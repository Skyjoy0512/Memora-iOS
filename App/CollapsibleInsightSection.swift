import SwiftUI

/// One summary section whose heading folds its content away. What is folded is
/// remembered per section, so a section the user does not read stays closed on
/// every meeting.
struct CollapsibleInsightSection<Content: View>: View {
  var section: MeetingInsightSection
  var showsDivider = true
  @ViewBuilder var content: Content

  @AppStorage private var isCollapsed: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    _ section: MeetingInsightSection,
    showsDivider: Bool = true,
    @ViewBuilder content: () -> Content
  ) {
    self.section = section
    self.showsDivider = showsDivider
    self.content = content()
    _isCollapsed = AppStorage(wrappedValue: section != .summary, "meetingInsight.collapsed.\(section.rawValue)")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if showsDivider {
        Divider()
          .padding(.bottom, 6)
      }

      Button {
        withAnimation(reduceMotion ? nil : MemoraMotion.control) {
          isCollapsed.toggle()
        }
      } label: {
        HStack(spacing: 8) {
          Label {
            Text(section.title)
          } icon: {
            if let artwork = section.artwork {
              ArtworkIcon(artwork: artwork, size: 20)
            } else {
              Image(icon: section.icon)
            }
          }
            .font(.title3.bold())
            .foregroundStyle(.primary)
          Spacer(minLength: 8)
          Image(icon: .chevronDown)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isCollapsed ? -90 : 0))
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityValue(isCollapsed ? "折りたたみ" : "展開")
      .accessibilityHint(isCollapsed ? "タップして表示" : "タップして非表示")
      .accessibilityAddTraits(.isHeader)

      if !isCollapsed {
        content
          .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
