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
  var save: (() -> Void)? = nil
  var retry: () -> Void
  var saveSkill: (() -> Void)? = nil
  var saveTitle = "回答を資料に保存"
  var currentText: (() -> String)? = nil
  var configureAI: (() -> Void)? = nil
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var didCopy = false
  @State private var resetTask: Task<Void, Never>?
  @State private var selection: AIAnswerTextPresentation?
  @State private var sharing: AIAnswerTextPresentation?

  var body: some View {
    HStack(spacing: 2) {
      Button(didCopy ? "コピーしました" : "コピー", icon: didCopy ? .checkmark : .docOnDoc) {
        copy()
      }
      .contentTransition(reduceMotion ? .identity : .opacity)
      .disabled(text.isEmpty)

      if isSpeaking, let readAloud {
        Button("読み上げを停止", icon: .stopFill, action: readAloud)
      }

      Menu {
        Button("共有", icon: .squareAndArrowUp) {
          let value = currentText?() ?? text
          guard !value.isEmpty else { return }
          sharing = AIAnswerTextPresentation(text: value)
        }
        .disabled(text.isEmpty)
        if !isSpeaking, let readAloud {
          Button("読み上げ", icon: .speakerWave2Fill, action: readAloud)
        }
        Button("テキストを選択…", icon: .textAlignleft) {
          let value = currentText?() ?? text
          guard !value.isEmpty else { return }
          selection = AIAnswerTextPresentation(text: value)
        }
          .disabled(text.isEmpty)
        if let save {
          Button(saveTitle, icon: .docText, action: save)
        }
        if let saveSkill {
          Button("回答からスキルを作成", icon: .squareAndPencil, action: saveSkill)
            .disabled(text.isEmpty)
        }
        if canRetry {
          Divider()
          Button("もう一度回答", icon: .arrowClockwise, action: retry)
        }
        if let configureAI {
          Divider()
          Button("AIモデルの設定", icon: .cpu, action: configureAI)
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
    .sheet(item: $selection) { presentation in
      AIAnswerTextSelectionView(text: presentation.text)
    }
    .sheet(item: $sharing) { presentation in ActivityView(items: [presentation.text]) }
    .onChange(of: text) { _, _ in
      resetTask?.cancel()
      didCopy = false
      selection = nil
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
