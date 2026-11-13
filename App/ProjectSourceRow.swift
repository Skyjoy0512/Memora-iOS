import SwiftUI

struct ProjectSourceRow: View {
  var source: ProjectSource
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let metadata = [source.kindLabel, MemoraFormat.relativeDate(source.createdAt)]
      + (source.processingStatus == .ready && source.textCoverage == .partial ? ["一部の内容"] : [])
    let layout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: MemoraSpacing.sm))
      : AnyLayout(HStackLayout(alignment: .top, spacing: MemoraSpacing.md))
    layout {
      ProjectSourceThumbnail(source: source)
      VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
        Text(source.title).font(MemoraTypography.body.weight(.medium))
          .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
          .fixedSize(horizontal: false, vertical: true)
        Text(metadata.joined(separator: " · "))
          .font(MemoraTypography.metadata).foregroundStyle(MemoraPalette.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        if let status = additionalStatus {
          Text(status).font(MemoraTypography.metadata).foregroundStyle(MemoraPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, minHeight: ProjectLayout.minimumRowHeight, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private var additionalStatus: String? {
    guard source.processingStatus == .ready else { return source.statusLabel }
    if source.summaryStatus == .pending || source.summaryStatus == .processing { return "準備中" }
    if source.summaryStatus == .failed || source.summaryStatus == .unavailable ||
      source.summaryError?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
      return "要約を作成できませんでした"
    }
    return source.canProvideText ? nil : "内容未取得"
  }
}
