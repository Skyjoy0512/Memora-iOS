import SwiftUI
import UIKit

struct AIResponseCodeBlock: View {
  var language: String?
  var code: String
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var didCopy = false
  @State private var resetTask: Task<Void, Never>?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(language.flatMap { $0.isEmpty ? nil : $0 } ?? "コード")
          .font(.caption.monospaced()).foregroundStyle(.secondary)
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
      .padding(.leading, 14).padding(.trailing, 4)
      Divider()
      ScrollView(.horizontal) {
        Text(verbatim: code)
          .font(.system(.subheadline, design: .monospaced))
          .textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
          .padding(14)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(MemoraPalette.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
    .onDisappear { resetTask?.cancel() }
  }
}
