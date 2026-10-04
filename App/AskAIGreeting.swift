import SwiftUI

/// What Ask AI opens with before anything is asked: a greeting, a few things
/// to try (each one sends itself when tapped), and a tip about memory.
struct AskAIGreeting: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown = 0

  private static let prompts = [
    "わたしについて何を覚えている？",
    "今週決まったことは？",
    "最新の会議のフォローアップメールを下書きして",
    "未完了のタスクを教えて"
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      bubble(0) {
        Text(greeting)
      }

      bubble(1) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Memoraです。会議の記録を探して答えたり、メールの下書きや予定の登録まで片付けたりします。変える前には必ず確認します。たとえば：")
          ForEach(Self.prompts, id: \.self) { prompt in
            Button {
              model.sendAIChat(prompt)
            } label: {
              Text("「\(prompt)」")
                .foregroundStyle(.tint)
                .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("この内容で話しかけます")
          }
        }
      }

      bubble(2) {
        Text("ヒント：記録やメモが増えるほど、あなたに合わせて答えられるようになります。 \(Image(icon: .sparkles))")
      }
    }
    .onAppear { reveal() }
  }

  private var greeting: String {
    let name = model.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? "こんにちは！" : "こんにちは、\(name)さん！"
  }

  /// The lines arrive one after another, as messages do.
  private func bubble(_ index: Int, @ViewBuilder content: () -> some View) -> some View {
    content()
      .font(.body)
      .lineSpacing(3)
      .frame(maxWidth: .infinity, alignment: .leading)
      .opacity(shown > index ? 1 : 0)
      .offset(y: shown > index || reduceMotion ? 0 : 8)
  }

  private func reveal() {
    guard shown == 0 else { return }
    Task { @MainActor in
      for index in 1...3 {
        withAnimation(reduceMotion ? nil : MemoraMotion.screen) { shown = index }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 280))
      }
    }
  }
}
