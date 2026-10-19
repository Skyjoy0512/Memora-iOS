import SwiftUI

struct MemoraLoadingContainer<Content: View>: View {
  var state: MemoraLoadingState
  var label: String
  var activityID: UUID?
  var failure: String?
  var retry: (() -> Void)?
  var cancel: (() -> Void)?
  @ViewBuilder var content: Content
  @State private var presentation = Presentation()

  var body: some View {
    let activity = Activity(state: state, id: activityID)
    let stage = presentation.activity == activity ? presentation.stage : 0
    VStack(alignment: .leading, spacing: 12) {
      content
      if state == .loading {
        MemoraSkeleton().opacity(stage >= 1 ? 1 : 0)
        if stage >= 2 { Text(label).font(.footnote).foregroundStyle(.secondary) }
      } else if state == .refreshing {
        ProgressView(label).font(.footnote)
      }
      if state == .failed, let failure {
        Label(failure, icon: .exclamationmarkTriangle)
          .font(MemoraTypography.secondary).foregroundStyle(MemoraPalette.danger)
        if let retry { Button("再試行", action: retry).buttonStyle(MemoraButtonStyle(emphasis: .secondary)) }
      }
      if state.isWorking, stage >= 3, let cancel {
        Button("読み込みを停止", action: cancel).frame(minHeight: 44)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .task(id: activity) {
      presentation = Presentation(activity: activity)
      guard state.isWorking else { return }
      let clock = ContinuousClock()
      let start = clock.now
      do {
        for delay in [MemoraLoadingPolicy.skeletonDelay, MemoraLoadingPolicy.explanationDelay, MemoraLoadingPolicy.actionsDelay] {
          try await clock.sleep(until: start.advanced(by: delay))
          try Task.checkCancellation()
          presentation = Presentation(activity: activity,
            stage: MemoraLoadingPolicy.stage(after: start.duration(to: clock.now)))
        }
      } catch { }
    }
  }

  private struct Activity: Equatable {
    var state: MemoraLoadingState
    var id: UUID?
  }

  private struct Presentation {
    var activity: Activity?
    var stage = 0
  }
}
