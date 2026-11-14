import SwiftUI

struct ProcessingOverview: View {
  @Environment(MemoraModel.self) private var model
  var meeting: Meeting

  var body: some View {
    WorkingStatus(label: label, startedAt: model.processing.startedAt[meeting.id])
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(minHeight: MemoraSpacing.touchTarget)
  }

  private var label: String {
    switch meeting.status {
    case .importing: "音声を取り込んでいます"
    case .transcribing: "文字起こししています"
    case .organizing: "要約しています"
    default: "準備しています"
    }
  }
}
