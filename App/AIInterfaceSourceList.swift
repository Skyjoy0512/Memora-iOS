import SwiftUI

/// A read-only list of the records an answer was built from.
///
/// The record's stored name leads, an optional model note sits beneath it, and
/// a grounded metadata line names the kind and how many stored excerpts the
/// answer read. Only a record that still exists and is currently permitted
/// becomes a link; the rest are counted and reported instead of being dropped.
/// The card-with-header idea follows OpenUI's `Sources` (MIT, 8d9c4c3b) as an
/// independent SwiftUI implementation.
struct AIInterfaceSourceList: View {
  var items: [NativeAIInterface.Item]
  var sources: [UUID: AIChatSource]
  var messageID: UUID?
  var canOpen: (UUID) -> Bool

  var body: some View {
    let rows = AIInterfaceSourceListModel.rows(items: items, sources: sources, isAvailable: canOpen)
    let available = rows.filter(\.isAvailable)
    let unavailableCount = rows.count - available.count
    VStack(alignment: .leading, spacing: 0) {
      if available.isEmpty {
        Text("参照できる資料がありません。必要な情報を改めて依頼してください。")
          .font(.footnote).foregroundStyle(MemoraPalette.textSecondary)
      } else {
        ForEach(Array(available.enumerated()), id: \.element.id) { index, row in
          link(row)
          if index < available.count - 1 || unavailableCount > 0 {
            Rectangle().fill(MemoraPalette.border).frame(height: 1)
          }
        }
        if unavailableCount > 0 {
          Text("ほか\(unavailableCount)件の資料は現在参照できません。")
            .font(.caption).foregroundStyle(MemoraPalette.textSecondary)
            .padding(.top, 8)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private func link(_ row: AIInterfaceSourceRow) -> some View {
    if let messageID {
      NavigationLink {
        AIInterfaceReferenceDestination(messageID: messageID, target: .meeting(row.id))
      } label: {
        label(row)
      }
      .accessibilityHint("資料を開きます")
    } else {
      label(row)
    }
  }

  private func label(_ row: AIInterfaceSourceRow) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(icon: .docText)
        .font(.body)
        .foregroundStyle(MemoraPalette.textSecondary)
        .frame(width: 22)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 3) {
        Text(row.title)
          .font(.subheadline)
          .foregroundStyle(MemoraPalette.textPrimary)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
        if let supplement = row.supplement, !supplement.isEmpty {
          Text(supplement)
            .font(.caption)
            .foregroundStyle(MemoraPalette.textSecondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        Text(metadata(row))
          .font(.caption2)
          .foregroundStyle(MemoraPalette.textSecondary)
      }
      Spacer(minLength: 0)
      Image(icon: .chevronRight)
        .font(.footnote)
        .foregroundStyle(MemoraPalette.textSecondary)
        .padding(.top, 2)
        .accessibilityHidden(true)
    }
    .padding(.vertical, 10)
    .frame(minHeight: 44)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private func metadata(_ row: AIInterfaceSourceRow) -> String {
    row.excerptCount > 0 ? "会議 · 引用\(row.excerptCount)件" : "会議"
  }
}
