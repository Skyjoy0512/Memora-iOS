import SwiftUI
import UIKit

// Adapted from chatgpt-ios-ui ChatGPTView's response action row and text-selection
// presentation (MIT, dc6e6a52). Copyright (c) 2026 Bryan Ramirez-Gonzalez and contributors.
// See Resources/ChatGPTUI-LICENSE.txt. Host callbacks retain Memora's live permission checks.
struct AIResponseActionBar: View {
  var text: String
  var canRetry = false
  var isSpeaking = false
  var readAloud: (() -> Void)?
  var save: () -> Void
  var retry: () -> Void
  var saveSkill: (() -> Void)? = nil
  var saveTitle = "回答を資料に保存"
  var currentText: (() -> String)? = nil
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var didCopy = false
  @State private var resetTask: Task<Void, Never>?
  @State private var selectsText = false
  @State private var selectionText = ""
  @State private var shareText = ""
  @State private var isSharing = false

  var body: some View {
    HStack(spacing: 2) {
      Button(didCopy ? "コピーしました" : "コピー", icon: didCopy ? .checkmark : .docOnDoc) {
        copy()
      }
      .contentTransition(reduceMotion ? .identity : .opacity)
      .disabled(text.isEmpty)

      Button("共有", icon: .squareAndArrowUp) {
        shareText = currentText?() ?? text
        isSharing = !shareText.isEmpty
      }
        .disabled(text.isEmpty)

      if let readAloud {
        Button(isSpeaking ? "読み上げを停止" : "読み上げ",
          icon: isSpeaking ? .stopFill : .speakerWave2Fill, action: readAloud)
      }

      Menu {
        Button("テキストを選択…", icon: .textAlignleft) {
          selectionText = currentText?() ?? text
          selectsText = true
        }
          .disabled(text.isEmpty)
        Button(saveTitle, icon: .docText, action: save)
        if let saveSkill {
          Button("回答からスキルを作成", icon: .squareAndPencil, action: saveSkill)
            .disabled(text.isEmpty)
        }
        if canRetry {
          Divider()
          Button("もう一度回答", icon: .arrowClockwise, action: retry)
        }
      } label: {
        Label("回答のその他の操作", icon: .ellipsis)
      }
      .menuOrder(.fixed)
    }
    .labelStyle(.iconOnly)
    .buttonStyle(AIResponseActionStyle())
    .foregroundStyle(.secondary)
    .padding(.leading, -9)
    .sheet(isPresented: $selectsText) {
      AIAnswerTextSelectionView(text: selectionText)
    }
    .sheet(isPresented: $isSharing) { ActivityView(items: [shareText]) }
    .onChange(of: text) { _, _ in
      resetTask?.cancel()
      didCopy = false
      selectsText = false
    }
    .onDisappear { resetTask?.cancel() }
  }

  private func copy() {
    UIPasteboard.general.string = currentText?() ?? text
    InteractionFeedback.shared.send(.success)
    withAnimation(reduceMotion ? nil : MemoraMotion.control) { didCopy = true }
    resetTask?.cancel()
    resetTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      withAnimation(reduceMotion ? nil : MemoraMotion.control) { didCopy = false }
    }
  }
}

private struct AIResponseActionStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: MemoraIconMetrics.glyph, weight: .regular))
      .frame(width: 44, height: 44).contentShape(Rectangle())
      .opacity(configuration.isPressed ? 0.5 : 1)
  }
}
