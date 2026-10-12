import SwiftUI

struct ProjectChatRow: View {
  var thread: ProjectChatThread

  var body: some View {
    NavigationLink(value: LibraryRoute.projectChat(thread.id)) {
      VStack(alignment: .leading, spacing: 4) {
        Text(thread.title).font(.body.weight(.semibold)).lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
        Text(thread.updatedAt.formatted(date: .abbreviated, time: .shortened))
          .font(.footnote).foregroundStyle(.secondary)
        if thread.projectID == nil { Text("保管した会話").font(.footnote).foregroundStyle(.secondary) }
      }
      .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
      .contentShape(Rectangle())
      .accessibilityElement(children: .combine)
    }.buttonStyle(.plain)
  }
}
