import SwiftUI

struct ProjectListRow: View {
  var space: MemoraSpace
  var zoomNamespace: Namespace.ID
  var recordCount: Int
  var latestRecordDate: Date?
  var rename: () -> Void
  var share: () -> Void
  var delete: () -> Void

  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 0) {
      NavigationLink(value: LibraryRoute.space(space.id)) {
        HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: MemoraSpacing.md) {
          MemoraInterfaceIcon(icon: space.icon)
          VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
            Text(space.name)
              .font(.body.weight(.medium))
              .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
              .fixedSize(horizontal: false, vertical: true)
            if recordCount > 0 { detail("記録\(recordCount)件") }
            if typeSize.isAccessibilitySize, let latestActivity { detail(latestActivity) }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          if !typeSize.isAccessibilitySize, let latestActivity {
            detail(latestActivity).fixedSize(horizontal: true, vertical: false)
          }
        }
        .padding(.vertical, MemoraSpacing.xs)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .matchedTransitionSource(id: space.id, in: zoomNamespace)
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .combine)
      .accessibilityLabel("\(space.name)、\(metadata)")
      .accessibilityHint("プロジェクトを開きます")
      .contextMenu { actions }

      Menu { actions } label: {
        Image(icon: .ellipsis)
          .foregroundStyle(.secondary)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel("\(space.name)の操作")
      .tint(MemoraPalette.textPrimary)
    }
  }

  private func detail(_ value: String) -> some View {
    Text(value)
      .font(MemoraTypography.metadata)
      .foregroundStyle(MemoraPalette.textSecondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var latestActivity: String? {
    latestRecordDate.map(MemoraFormat.relativeDate)
  }

  private var metadata: String {
    guard recordCount > 0 else { return "まだ記録がありません" }
    guard let latestActivity else { return "記録\(recordCount)件" }
    return "記録\(recordCount)件、最新の記録は\(latestActivity)"
  }

  @ViewBuilder private var actions: some View {
    Button("名前を変更", icon: .pencil, action: rename)
    Button("チームで共有", icon: .personBadgePlus, action: share)
    Divider()
    Button("削除", icon: .trash, role: .destructive, action: delete)
  }
}
