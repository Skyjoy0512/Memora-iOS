import SwiftUI

struct MemoraLoadingContainer<Content: View>: View {
  var state: MemoraLoadingState
  var label: String
  var activityID: UUID?
  var failure: String?
  var retry: (() -> Void)?
  var cancel: (() -> Void)?
  @ViewBuilder var content: Content
  @State private var stage = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      content
      if state == .loading {
        MemoraSkeleton().opacity(stage >= 1 ? 1 : 0)
        if stage >= 2 { Text(label).font(.footnote).foregroundStyle(.secondary) }
      } else if state == .refreshing {
        ProgressView(label).font(.footnote)
      }
      if state == .failed, let failure {
        Text(failure).font(.subheadline).foregroundStyle(.secondary)
        if let retry { Button("再試行", action: retry).frame(minHeight: 44) }
      }
      if state.isWorking, stage >= 3, let cancel {
        Button("読み込みを停止", action: cancel).frame(minHeight: 44)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .task(id: Activity(state: state, id: activityID)) {
      stage = 0
      guard state.isWorking else { return }
      let clock = ContinuousClock()
      let start = clock.now
      do {
        for delay in [MemoraLoadingPolicy.skeletonDelay, MemoraLoadingPolicy.explanationDelay, MemoraLoadingPolicy.actionsDelay] {
          try await clock.sleep(until: start.advanced(by: delay))
          try Task.checkCancellation()
          stage = MemoraLoadingPolicy.stage(after: start.duration(to: clock.now))
        }
      } catch { }
    }
  }

  private struct Activity: Equatable {
    var state: MemoraLoadingState
    var id: UUID?
  }
}
