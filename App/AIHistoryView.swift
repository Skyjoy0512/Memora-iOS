import SwiftUI

struct AIHistoryView: View {
  @Environment(\.dismiss) private var dismiss
  var entries: [AIConversationEntry]
  /// Asks the stored question again, as a separate choice from reading it.
  var ask: (String) -> Void
  var delete: (UUID) -> Void

  var body: some View {
    NavigationStack {
      Group {
        if entries.isEmpty {
          ContentUnavailableView("まだ履歴がありません", icon: .clockArrowCirclepath)
        } else {
          List {
            ForEach(entries) { entry in
              NavigationLink {
                AIHistoryDetailView(entry: entry, ask: ask)
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(entry.question)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                  Text("\(entry.scopeLabel) · \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
              }
            }
            .onDelete { indexSet in
              for index in indexSet {
                delete(entries[index].id)
              }
            }
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
