import SwiftUI

struct ProcessingOverview: View {
  @Environment(MemoraModel.self) private var model
  var meeting: Meeting

  var body: some View {
    WorkingStatus(label: "準備しています", startedAt: model.processing.startedAt[meeting.id])
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(MemoraSpacing.lg)
      .memoraCard()
  }
}
