import SwiftUI

struct ProjectCard: View {
  var space: MemoraSpace
  var recordCount: Int
  var taskCount: Int
  var latestRecordDate: Date?
  var rename: () -> Void
  var share: () -> Void
  var delete: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      NavigationLink(value: LibraryRoute.space(space.id)) {
        VStack(alignment: .leading, spacing: 16) {
          HStack(alignment: .center, spacing: 12) {
            Image(icon: space.icon, size: 20)
              .frame(width: 44, height: 44)
              .background(MemoraPalette.selection, in: RoundedRectangle(cornerRadius: MemoraRadius.field))
              .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
              Text(space.name)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
              if let latestRecordDate {
                Text("最新の記録 \(latestRecordDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: "ja_JP"))))")
                  .font(.caption).foregroundStyle(MemoraPalette.cardTextSecondary)
              }
            }
          }
          ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { counts }
            VStack(alignment: .leading, spacing: 8) { counts }
          }
          .font(MemoraTypography.secondary)
          .foregroundStyle(MemoraPalette.cardTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, MemoraSpacing.lg)
        .padding(.vertical, MemoraSpacing.lg)
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .combine)
      .accessibilityHint("プロジェクトの記録とタスクを開きます")
      .contextMenu { actions }

      // A sibling menu keeps its taps separate from the navigation link.
      Menu { actions } label: {
        Image(icon: .ellipsis, size: 17)
          .foregroundStyle(MemoraPalette.cardTextSecondary)
          .frame(width: 44, height: 44)
          .contentShape(Rectangle())
      }
      .tint(MemoraPalette.textPrimary)
      .accessibilityLabel("\(space.name)の操作")
      .padding(.top, MemoraSpacing.sm)
      .padding(.trailing, MemoraSpacing.sm)
    }
    .memoraCard(fill: MemoraPalette.card)
  }

  @ViewBuilder private var counts: some View {
    Label("記録 \(recordCount)件", icon: .waveform)
    Label("未完了タスク \(taskCount)件", icon: .checklist)
  }

  @ViewBuilder private var actions: some View {
    Button("名前を変更", icon: .pencil, action: rename)
    Button("チームで共有", icon: .personBadgePlus, action: share)
    Divider()
    Button("削除", icon: .trash, role: .destructive, action: delete)
  }
}
