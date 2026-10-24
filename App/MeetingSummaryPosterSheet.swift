import SwiftUI
import UIKit

struct MeetingSummaryPosterSheet: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var snapshot: MeetingSummaryPosterSnapshot
  @State private var image: UIImage?
  @State private var showsText = false
  @State private var isEnlarged = false
  @State private var failure: String?
  @State private var confirmsExport = false
  @State private var isSharing = false
  @State private var exportURL: URL?
  @State private var availableWidth: CGFloat = 320

  var body: some View {
    let isCurrent = snapshot.isCurrent(in: model)
    NavigationStack {
      Group {
        if !isCurrent {
          ContentUnavailableView("要約またはアクセス状態が変わりました", icon: .docText,
                                 description: Text("閉じてから、現在の要約で作り直してください。"))
        } else {
          VStack(spacing: 12) {
            Picker("表示", selection: $showsText) {
              Text("画像").tag(false)
              Text("全文").tag(true)
            }
            .pickerStyle(.segmented).padding(.horizontal)
            if showsText {
              ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                  Text(snapshot.title).font(.title2.bold())
                  MarkdownDocumentView(markdown: snapshot.summary, isLazy: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                .textSelection(.enabled)
              }
            } else if let image {
              ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image).resizable().scaledToFit()
                  .frame(width: isEnlarged ? 720 : min(720, availableWidth))
                  .accessibilityLabel("\(snapshot.title)の1枚サマリー。要約本文の見出しと項目に沿って構成しています。全文タブで全内容を読めます")
                  .accessibilityIdentifier("summary.poster.image")
                  .padding(.horizontal, 16)
              }
              Button(isEnlarged ? "全体を表示" : "拡大して読む") { isEnlarged.toggle() }
                .frame(minHeight: 44)
              Text("端末内で作成・\(Int(image.size.width * image.scale)) × \(Int(image.size.height * image.scale)) PNG\n抜粋のため、条件や出典を含む全文もご確認ください。")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal)
            } else if let failure {
              ContentUnavailableView("画像を作成できませんでした", icon: .photo, description: Text(failure))
              Button("再試行", action: render).frame(minHeight: 44)
            } else {
              ProgressView("画像を作成しています").frame(maxHeight: .infinity)
            }
          }
          .padding(.bottom)
        }
      }
      .navigationTitle("1枚サマリー")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
        ToolbarItem(placement: .topBarLeading) {
          Button("PNGを共有・保存", icon: .squareAndArrowUp) { confirmsExport = true }
            .disabled(image == nil || !isCurrent)
            .accessibilityIdentifier("summary.poster.export")
        }
      }
      .background {
        GeometryReader { proxy in
          Color.clear.onAppear { availableWidth = max(240, proxy.size.width - 32) }
            .onChange(of: proxy.size.width) { _, width in availableWidth = max(240, width - 32) }
        }
      }
      .task { await Task.yield(); render() }
      .onChange(of: isCurrent) { _, current in
        if !current { image = nil; isSharing = false; confirmsExport = false; cleanUp() }
      }
      .confirmationDialog("要約を画像として共有・保存しますか？", isPresented: $confirmsExport, titleVisibility: .visible) {
        Button("共有先・保存先を選ぶ") { export() }
        Button("キャンセル", role: .cancel) {}
      } message: {
        Text("要約の抜粋が画像に含まれます。機密情報や共有範囲を確認してください。自動送信はしません。")
      }
      .sheet(isPresented: $isSharing, onDismiss: cleanUp) {
        if let exportURL, snapshot.isCurrent(in: model) {
          ActivityView(items: [exportURL], onComplete: { isSharing = false })
        }
      }
      .alert("画像を書き出せませんでした", isPresented: Binding(get: { failure != nil && image != nil }, set: { if !$0 { failure = nil } })) {
        Button("OK", role: .cancel) { failure = nil }
      } message: { Text(failure ?? "") }
      .onDisappear(perform: cleanUp)
    }
  }

  private func render() {
    guard !Task.isCancelled, snapshot.isCurrent(in: model) else { return }
    failure = nil
    do {
      image = try MeetingSummaryPosterRenderer.render(MeetingSummaryPosterContent(
        title: snapshot.title, date: snapshot.createdAt.formatted(date: .abbreviated, time: .omitted), summary: snapshot.summary))
    } catch { failure = "本文は保持されています。もう一度お試しください。" }
  }

  private func export() {
    guard snapshot.isCurrent(in: model), let image else { return }
    cleanUp()
    do { exportURL = try MeetingSummaryPosterRenderer.export(image); isSharing = true }
    catch { failure = "保存先の空き容量などをご確認ください。画像は再試行できます。" }
  }

  private func cleanUp() {
    if let exportURL { ArtifactExportFile.removeTemporary([exportURL]) }
    exportURL = nil
  }
}
