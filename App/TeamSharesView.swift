import SwiftUI

/// What teammates have shared with this person through CloudKit. Shared items
/// are snapshots the owner publishes, so they are shown here read-only and
/// update when the owner changes them.
struct TeamSharesView: View {
  @Environment(MemoraModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    List {
      if let message = model.cloudSharing.availabilityMessage {
        Section {
          Label(message, systemImage: "icloud.slash")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }

      if model.cloudSharing.receivedItems.isEmpty {
        ContentUnavailableView {
          Label("共有されたものはありません", systemImage: "person.3")
        } description: {
          Text("チームのメンバーがプロジェクトや記録を共有すると、ここに表示されます。")
        }
      } else {
        ForEach(model.cloudSharing.receivedItems) { item in
          VStack(alignment: .leading, spacing: 4) {
            Label(item.title, systemImage: item.kind == "project" ? "folder" : "doc.text")
              .font(.body.weight(.medium))
            Text(item.kind == "project" ? "プロジェクト" : "記録")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel("\(item.title)、\(item.kind == "project" ? "プロジェクト" : "記録")")
        }
      }
    }
    .navigationTitle("チームで共有されたもの")
    .navigationBarTitleDisplayMode(.inline)
    .task {
      await model.cloudSharing.refreshAvailability()
      await model.cloudSharing.refreshReceived()
    }
    .onChange(of: scenePhase) { _, phase in
      guard phase == .active else { return }
      Task { await model.cloudSharing.refreshReceived() }
    }
  }
}
