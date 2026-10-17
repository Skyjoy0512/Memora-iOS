#if DEBUG
import SwiftUI

/// A display-only fixture for the structured-answer parts that need stored
/// records to look real (SourceList, TaskProgress). The records here are made
/// up and live only in this view, so nothing is read from or written to the
/// store; the gallery route only shows how the parts draw. The parts drawn are
/// the same ones Ask AI uses, with a nil message ID so no row becomes a link.
struct AIInterfaceStructuredExampleView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 32) {
        Text("表示検証用の例です。実際の記録・AI回答ではありません。")
          .font(.footnote).foregroundStyle(MemoraPalette.textSecondary)
        section("根拠一覧（通常）") {
          AIInterfaceSourceList(items: Self.availableItems, sources: Self.sources,
            messageID: nil, canOpen: { _ in true })
        }
        section("根拠一覧（失効・削除を含む）") {
          AIInterfaceSourceList(items: Self.mixedItems, sources: Self.sources,
            messageID: nil, canOpen: { $0 != Self.revokedID })
        }
        section("根拠一覧（参照できる資料なし）") {
          AIInterfaceSourceList(items: Self.emptyItems, sources: [:],
            messageID: nil, canOpen: { _ in false })
        }
        section("進捗（一部完了・内訳あり）") {
          AIInterfaceTaskProgress(tasks: Self.partialTasks)
        }
        section("進捗（全完了）") {
          AIInterfaceTaskProgress(tasks: Self.completedTasks)
        }
        section("進捗（1件のみ）") {
          AIInterfaceTaskProgress(tasks: Self.singleTask)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(18)
    }
    .background(MemoraPalette.background)
    .navigationTitle("資料・進捗の表示確認").navigationBarTitleDisplayMode(.inline)
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).font(.headline)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

extension AIInterfaceStructuredExampleView {
  private static let meetingA = UUID()
  private static let meetingB = UUID()
  private static let meetingC = UUID()
  private static let revokedID = UUID()
  private static let deletedID = UUID()

  private static let sources: [UUID: AIChatSource] = [
    meetingA: AIChatSource(meetingID: meetingA, title: "WeeklySync 定例（9/29）",
      excerpts: [.init(text: "来週のリリースを確認した。", start: 12), .init(text: "担当を割り当てた。", start: 40), .init(text: "次回は10/6。", start: 88)]),
    meetingB: AIChatSource(meetingID: meetingB,
      title: "新規事業キックオフ 議事録（長い資料名の折り返しを確認するためのタイトル）", excerpts: [.init(text: "対象顧客を絞る。", start: 5)]),
    meetingC: AIChatSource(meetingID: meetingC, title: "田中さんとの1on1",
      excerpts: [.init(text: "来期の目標を話した。", start: 20), .init(text: "評価の観点を共有。", start: 60)]),
    revokedID: AIChatSource(meetingID: revokedID, title: "権限が外れた資料", excerpts: [])
  ]

  private static let availableItems: [NativeAIInterface.Item] = [
    .init(id: "a", title: nil, detail: "決定事項と担当の確認", referenceID: meetingA, cells: nil, value: nil, action: nil),
    .init(id: "b", title: nil, detail: nil, referenceID: meetingB, cells: nil, value: nil, action: nil),
    .init(id: "c", title: nil, detail: "来期の目標について", referenceID: meetingC, cells: nil, value: nil, action: nil)
  ]

  private static let mixedItems: [NativeAIInterface.Item] = [
    .init(id: "a", title: nil, detail: "決定事項と担当の確認", referenceID: meetingA, cells: nil, value: nil, action: nil),
    .init(id: "revoked", title: nil, detail: nil, referenceID: revokedID, cells: nil, value: nil, action: nil),
    .init(id: "deleted", title: "削除された資料", detail: nil, referenceID: deletedID, cells: nil, value: nil, action: nil),
    .init(id: "c", title: nil, detail: nil, referenceID: meetingC, cells: nil, value: nil, action: nil)
  ]

  private static let emptyItems: [NativeAIInterface.Item] = [
    .init(id: "missing", title: nil, detail: nil, referenceID: UUID(), cells: nil, value: nil, action: nil)
  ]

  private static let partialTasks: [MemoraTask] = [
    MemoraTask(id: UUID(), title: "議事録を共有する", isCompleted: true),
    MemoraTask(id: UUID(), title: "見積もりを送る", isCompleted: false),
    MemoraTask(id: UUID(), title: "来週の資料を準備する", isCompleted: false),
    MemoraTask(id: UUID(), title: "田中さんに確認する", isCompleted: false)
  ]

  private static let completedTasks: [MemoraTask] = [
    MemoraTask(id: UUID(), title: "議事録を共有する", isCompleted: true),
    MemoraTask(id: UUID(), title: "見積もりを送る", isCompleted: true),
    MemoraTask(id: UUID(), title: "請求書を確認する", isCompleted: true)
  ]

  private static let singleTask: [MemoraTask] = [
    MemoraTask(id: UUID(), title: "議事録を共有する", isCompleted: false)
  ]
}
#endif
