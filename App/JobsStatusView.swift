import SwiftUI

/// Every transcription or summary still owed on this device, why it stopped,
/// and the one action that moves it on. Content first: no cards, no counters.
struct JobsStatusView: View {
  @Environment(MemoraModel.self) private var model
  @State private var retryTarget: RetryTarget?

  var body: some View {
    let rows = model.jobStatusRows
    List {
      if rows.isEmpty {
        Section {
          Text("処理待ちのジョブはありません。")
            .font(MemoraTypography.secondary)
            .foregroundStyle(.secondary)
        }
      } else {
        ForEach(rows) { row in
          Section {
            rowContent(row)
          }
        }
      }
    }
    .navigationTitle("処理の状況")
    .navigationBarTitleDisplayMode(.inline)
    .sheet(item: $retryTarget) { target in
      SummaryGenerationSheet(meetingID: target.id)
    }
  }

  private func rowContent(_ row: JobStatusRow) -> some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
      Text(row.title)
        .font(MemoraTypography.body)
        .accessibilityAddTraits(.isHeader)
      Text(statusText(row))
        .font(MemoraTypography.secondary)
        .foregroundStyle(row.state == .waiting ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
      Text(timingText(row))
        .font(MemoraTypography.metadata)
        .foregroundStyle(.secondary)
      Button(row.needsUserAction ? "もう一度要約する" : "要約の設定を開く") {
        retryTarget = RetryTarget(id: row.meetingID)
      }
      .font(MemoraTypography.secondary)
    }
    .padding(.vertical, MemoraSpacing.xs)
  }

  private func statusText(_ row: JobStatusRow) -> String {
    switch row.state {
    case .running(let stage): stage
    case .waiting: "待機中です。アプリを開いている間に順番に処理します。"
    case .stopped(let reason): reason
    }
  }

  private func timingText(_ row: JobStatusRow) -> String {
    let received = row.receivedAt.formatted(date: .abbreviated, time: .shortened)
    guard let startedAt = row.startedAt else { return "受付 \(received)" }
    return "受付 \(received)・開始 \(startedAt.formatted(date: .abbreviated, time: .shortened))"
  }
}

/// Identifies the record whose summary sheet is open.
private struct RetryTarget: Identifiable {
  var id: UUID
}
