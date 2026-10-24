import SwiftUI
import UIKit

struct MeetingSummaryPosterEntry: View {
  @Environment(MemoraModel.self) private var model
  var meetingID: UUID
  @State private var snapshot: MeetingSummaryPosterSnapshot?
  @State private var renderedSnapshot: MeetingSummaryPosterSnapshot?
  @State private var image: UIImage?
  @State private var failed = false

  var body: some View {
    let current = MeetingSummaryPosterSnapshot(meetingID: meetingID, model: model)
    if let current {
      VStack(alignment: .leading, spacing: 12) {
        Button {
          snapshot = MeetingSummaryPosterSnapshot(meetingID: meetingID, model: model)
        } label: {
          HStack(spacing: 12) {
            Text("1枚サマリー").font(.headline)
            Spacer(minLength: 0)
            Text("拡大・共有").font(.subheadline)
            Image(icon: .chevronRight, size: 16).accessibilityHidden(true)
          }
          .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("summary.poster.open")
        .accessibilityHint("画像を拡大し、確認してからPNGを共有・保存できます")

        if renderedSnapshot == current, let image {
          Image(uiImage: image).resizable().scaledToFit()
            .frame(maxWidth: .infinity)
            .overlay(Rectangle().stroke(MemoraPalette.border, lineWidth: 1))
            .accessibilityLabel("\(current.title)の1枚サマリー。要約本文の見出しと項目に沿って構成しています。下の要約本文で全内容を読めます")
            .accessibilityIdentifier("summary.poster.inline")
        } else if failed {
          Button("画像を再作成") { render(current) }
            .frame(minHeight: 44)
          Text("画像を作成できませんでした。要約本文はこの下で確認できます。")
            .font(.footnote).foregroundStyle(.secondary)
        } else {
          ProgressView("サマリー画像を作成しています")
            .frame(maxWidth: .infinity, minHeight: 100)
        }
        Text("要約の抜粋です。条件・根拠を含む全文はこの下にあります。")
          .font(.caption).foregroundStyle(.secondary)
      }
      .task(id: current) {
        image = nil
        failed = false
        await Task.yield()
        render(current)
      }
      .sheet(item: $snapshot) { MeetingSummaryPosterSheet(snapshot: $0) }
    }
  }

  private func render(_ current: MeetingSummaryPosterSnapshot) {
    guard !Task.isCancelled, current.isCurrent(in: model) else { return }
    do {
      let rendered = try MeetingSummaryPosterRenderer.render(MeetingSummaryPosterContent(
        title: current.title, date: current.createdAt.formatted(date: .abbreviated, time: .omitted), summary: current.summary))
      guard !Task.isCancelled, current.isCurrent(in: model) else { return }
      image = rendered
      renderedSnapshot = current
      failed = false
    } catch { failed = true }
  }
}
