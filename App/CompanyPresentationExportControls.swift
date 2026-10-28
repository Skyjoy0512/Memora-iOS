import SwiftUI

struct CompanyPresentationExportControls: View {
  var isWorking: Bool
  var blockedReason: String?
  var templateName: String?
  var templateVersion: Int?
  var notice: LocalizedStringResource?
  var start: () -> Void
  var cancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if isWorking {
        ShimmerText(text: "PPTXを書き出しています")
          .font(.subheadline)
        Button("キャンセル", role: .cancel, action: cancel)
          .frame(minHeight: MemoraSpacing.touchTarget)
          .accessibilityIdentifier("presentation.companyExport.cancel")
      } else {
        Button("会社PPTXを書き出す", action: start)
          .frame(minHeight: MemoraSpacing.touchTarget)
          .disabled(blockedReason != nil)
          .accessibilityIdentifier("presentation.companyExport.start")
        if let blockedReason {
          Text(blockedReason).font(.footnote).foregroundStyle(.secondary)
        } else if let templateName, let templateVersion {
          Text("書式: \(templateName) · v\(templateVersion)")
            .font(.footnote).foregroundStyle(.secondary)
        }
      }
      if let notice {
        Text(notice).font(.footnote).foregroundStyle(.secondary)
      }
    }
    .buttonStyle(.borderless)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
