import SwiftUI

struct DocumentArtifactHistoryView: View {
  var revisions: [DocumentArtifactRevision]
  var preview: (DocumentArtifactRevision) -> Void
  var share: (DocumentArtifactRevision) -> Void

  var body: some View {
    DisclosureGroup("以前のファイル（\(revisions.count)件）") {
      VStack(alignment: .leading, spacing: 16) {
        ForEach(revisions) { revision in
          VStack(alignment: .leading, spacing: 4) {
            Text("\(revision.format.rawValue) · 本文 v\(revision.contentRevision)")
              .font(.subheadline)
            if let version = revision.companyTemplateVersion {
              Text("会社書式 v\(version)").font(.footnote).foregroundStyle(.secondary)
            }
            Text("保管: \(revision.retainedAt, format: .dateTime.year().month().day().hour().minute())")
              .font(.footnote).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
              HStack(spacing: 16) { actions(revision) }
              VStack(alignment: .leading, spacing: 8) { actions(revision) }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityElement(children: .contain)
        }
      }
      .padding(.top, 8)
    }
    .buttonStyle(.borderless)
  }

  @ViewBuilder private func actions(_ revision: DocumentArtifactRevision) -> some View {
    Button("確認") { preview(revision) }
      .frame(minHeight: MemoraSpacing.touchTarget)
      .accessibilityLabel("以前の\(revision.format.rawValue)を確認、本文 v\(revision.contentRevision)")
    Button("保存・共有") { share(revision) }
      .frame(minHeight: MemoraSpacing.touchTarget)
      .accessibilityLabel("以前の\(revision.format.rawValue)を共有、本文 v\(revision.contentRevision)")
  }
}
