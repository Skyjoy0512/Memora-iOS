import SwiftUI
import UIKit

// Layout adapted from chatgpt-ios-ui ChatGPTCodeCard, MIT, dc6e6a52.
// Copyright (c) 2026 Bryan Ramirez-Gonzalez and contributors.
// See Resources/ChatGPTUI-LICENSE.txt. Copy actions remain local to Memora.
struct AIResponseCodeBlock: View {
  var language: String?
  var code: String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var didCopy = false
  @State private var resetTask: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text(language.flatMap { $0.isEmpty ? nil : $0 } ?? "コード")
          .font(.subheadline).foregroundStyle(.secondary)
        Spacer(minLength: 12)
        Button(didCopy ? "コピーしました" : "コードをコピー", icon: didCopy ? .checkmark : .docOnDoc) {
          UIPasteboard.general.string = code
          InteractionFeedback.shared.send(.success)
          didCopy = true
          resetTask?.cancel()
          resetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            didCopy = false
          }
        }
        .labelStyle(.iconOnly).buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
      }

      ScrollView(.horizontal) {
        Text(verbatim: code)
          .font(.system(.subheadline, design: .monospaced))
          .textSelection(.enabled).fixedSize(horizontal: true, vertical: false)

      }
      .scrollIndicators(.hidden)
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MemoraPalette.secondaryBackground, in: RoundedRectangle(cornerRadius: 24))
    .overlay {
      RoundedRectangle(cornerRadius: 24).stroke(.secondary.opacity(0.1), lineWidth: 1)
    }
    .onDisappear { resetTask?.cancel() }
  }
}
