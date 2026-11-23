import SwiftUI
import UIKit

/// Offered when a screenshot is taken: the answer is already on screen, so
/// offer to share it as a card instead of a raw capture, the way ChatGPT does.
struct AIAnswerShareSheet: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dismiss) private var dismiss
  var content: AIAnswerShareContent

  @State private var image: UIImage?
  @State private var exportURL: URL?
  @State private var didCopy = false
  @State private var resetTask: Task<Void, Never>?

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: MemoraSpacing.xs) {
        Text("整えた回答を共有")
          .font(.headline)
        Text("スクリーンショットの代わりに、読みやすいカード画像で共有できます。")
          .font(.footnote)
          .foregroundStyle(MemoraPalette.textSecondary)
          .multilineTextAlignment(.center)
      }
      .padding(.top, MemoraSpacing.xxl)
      .padding(.horizontal, MemoraSpacing.page)

      preview
        .padding(.top, MemoraSpacing.lg)
        .padding(.horizontal, MemoraSpacing.screen)

      Spacer(minLength: MemoraSpacing.md)

      HStack(alignment: .top, spacing: MemoraSpacing.xxl) {
        shareAction
        action(didCopy ? "コピーしました" : "コピー", icon: didCopy ? .checkmark : .docOnDoc, perform: copy)
        action("閉じる", icon: .xmark) { dismiss() }
      }
      .padding(.bottom, MemoraSpacing.page)
      .accessibilityIdentifier("ai.screenshotShare.actions")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(MemoraPalette.background)
    .presentationDetents([.fraction(0.8), .large])
    .presentationDragIndicator(.visible)
    .accessibilityIdentifier("ai.screenshotShare")
    .task(id: content.id) {
      await Task.yield()
      if image == nil { image = AIAnswerShareCardRenderer.render(content) }
      if let image, exportURL == nil {
        exportURL = try? AIAnswerShareCardRenderer.export(image)
      }
    }
    .onDisappear {
      resetTask?.cancel()
      cleanUp()
    }
  }

  @ViewBuilder
  private var preview: some View {
    if let image {
      Image(uiImage: image)
        .resizable()
        .scaledToFit()
        .frame(maxHeight: 400)
        .clipShape(RoundedRectangle(cornerRadius: MemoraRadius.bubble, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .accessibilityLabel("回答カードのプレビュー")
        .accessibilityIdentifier("ai.screenshotShare.preview")
    } else {
      ProgressView()
        .frame(maxWidth: .infinity, minHeight: 240)
    }
  }

  @ViewBuilder
  private var shareAction: some View {
    if let exportURL {
      ShareLink(item: exportURL) {
        actionLabel("共有", icon: .squareAndArrowUp)
      }
      .accessibilityLabel("共有")
    } else {
      Button {} label: { actionLabel("共有", icon: .squareAndArrowUp) }
        .buttonStyle(.plain)
        .disabled(true)
        .accessibilityLabel("共有")
    }
  }

  private func action(_ title: String, icon: MemoraIcon, perform: @escaping () -> Void) -> some View {
    Button {
      InteractionFeedback.shared.send(.tap)
      perform()
    } label: {
      actionLabel(title, icon: icon)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
  }

  private func actionLabel(_ title: String, icon: MemoraIcon) -> some View {
    VStack(spacing: MemoraSpacing.sm) {
      Image(icon: icon, size: MemoraIconMetrics.glyph)
        .foregroundStyle(MemoraPalette.textPrimary)
        .frame(width: 56, height: 56)
        .memoraGlass(in: Circle(), interactive: true, backed: false)
      Text(title)
        .font(.caption2)
        .foregroundStyle(MemoraPalette.textSecondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }
    .frame(minWidth: 76)
    .contentShape(Rectangle())
  }

  private func copy() {
    UIPasteboard.general.string = content.answer
    InteractionFeedback.shared.send(.success)
    withAnimation(reduceMotion ? nil : MemoraMotion.control) { didCopy = true }
    resetTask?.cancel()
    resetTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      withAnimation(reduceMotion ? nil : MemoraMotion.control) { didCopy = false }
    }
  }

  private func cleanUp() {
    guard let exportURL else { return }
    ArtifactExportFile.removeTemporary([exportURL])
    self.exportURL = nil
  }
}
