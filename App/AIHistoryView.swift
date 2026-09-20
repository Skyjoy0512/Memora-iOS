import SwiftUI

struct AIHistoryView: View {
  @Environment(\.dismiss) private var dismiss
  var entries: [AIConversationEntry]
  var select: (String) -> Void

  var body: some View {
    NavigationStack {
      Group {
        if entries.isEmpty {
          ContentUnavailableView("まだ履歴がありません", systemImage: "clock.arrow.circlepath")
        } else {
          List(entries) { entry in
            Button {
              select(entry.question)
            } label: {
              VStack(alignment: .leading, spacing: 4) {
                Text(entry.question)
                  .font(.body.weight(.medium))
                  .foregroundStyle(.primary)
                Text(entry.scopeLabel)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
          }
        }
      }
      .navigationTitle("質問履歴")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("完了") { dismiss() }
        }
      }
    }
  }
}
