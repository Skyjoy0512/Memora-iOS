import SwiftUI
import UIKit

struct MeetingSummaryPosterEntry: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID
  @State private var snapshot: MeetingSummaryPosterSnapshot?
  @State private var renderedSnapshot: MeetingSummaryPosterSnapshot?
  @State private var image: UIImage?
  @State private var failed = false
  @State private var document: MeetingInfographic?
  @State private var generationSnapshot: MeetingSummaryPosterSnapshot?

  var body: some View {
    let current = MeetingSummaryPosterSnapshot(meetingID: meetingID, model: model)
    if let current {
      VStack(alignment: .leading, spacing: 12) {
        if renderedSnapshot == current, let image {
          Image(uiImage: image).resizable().scaledToFit()
            .frame(maxWidth: .infinity)
            .overlay(Rectangle().stroke(MemoraPalette.border, lineWidth: 1))
            .accessibilityLabel(document.map { "\(current.title)の図解。\($0.content.headline.text)。\($0.content.panels.map { $0.title + ": " + $0.items.map(\.text).joined(separator: "、") }.joined(separator: "。"))。拡大・共有の全文タブで根拠を読めます" }
              ?? "\(current.title)の本文の抜粋。図解は未作成です。下の要約本文で全内容を読めます")
            .accessibilityIdentifier("summary.poster.inline")
            .accessibilityHint("長押しで拡大・共有や図解生成を選べます")
            .contextMenu {
              Button("拡大・共有") { snapshot = current }
                .accessibilityIdentifier("summary.poster.open")
              Button(document == nil ? "AIで図解を生成" : "AIで図解を再生成") { generationSnapshot = current }
                .accessibilityIdentifier("summary.infographic.prepare")
            }
            .accessibilityAction(named: "拡大・共有") { snapshot = current }
            .accessibilityAction(named: "AIで図解を生成") { generationSnapshot = current }
        } else if failed {
          Button("画像を再作成") { render(current) }
            .frame(minHeight: 44)
          Text("画像を作成できませんでした。要約本文はこの下で確認できます。")
            .font(.footnote).foregroundStyle(.secondary)
        } else {
          ProgressView("サマリー画像を作成しています")
            .frame(maxWidth: .infinity, minHeight: 100)
        }
      }
      .task(id: current) {
        image = nil
        failed = false
        await Task.yield()
        render(current)
      }
      .sheet(item: $snapshot) { MeetingSummaryPosterSheet(snapshot: $0) }
      .sheet(item: $generationSnapshot) { MeetingInfographicGenerationSheet(snapshot: $0) }
    }
  }

  private func render(_ current: MeetingSummaryPosterSnapshot) {
    guard !Task.isCancelled, current.isCurrent(in: model) else { return }
    do {
      let infographic = MeetingInfographicSample.resolve(current)
      let rendered = try MeetingSummaryPosterRenderer.render(MeetingSummaryPosterContent(
        title: current.title, date: current.createdAt.formatted(date: .abbreviated, time: .omitted), summary: current.summary), infographic: infographic)
      guard !Task.isCancelled, current.isCurrent(in: model) else { return }
      image = rendered
      document = infographic
      renderedSnapshot = current
      failed = false
    } catch { failed = true }
  }
}
