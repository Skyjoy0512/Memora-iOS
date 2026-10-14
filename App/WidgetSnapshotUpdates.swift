import SwiftUI

/// Observation for widget export stays outside the screen hierarchy.
struct WidgetSnapshotUpdates: ViewModifier {
  @Environment(MemoraModel.self) private var model
  @AppStorage("memora.appLock") private var locksApp = false

  func body(content: Content) -> some View {
    content
      .onChange(of: model.meetings) { _, _ in model.scheduleWidgetSnapshot() }
      .onChange(of: model.tasks) { _, _ in model.scheduleWidgetSnapshot() }
      .onChange(of: model.spaces) { _, _ in model.scheduleWidgetSnapshot() }
      .onChange(of: model.lifeLogEntries) { _, _ in model.scheduleWidgetSnapshot() }
      .onChange(of: model.currentTeamID) { _, _ in model.scheduleWidgetSnapshot() }
      .onChange(of: locksApp) { _, _ in model.scheduleWidgetSnapshot() }
      .onChange(of: model.isStoreProtected) { _, _ in model.scheduleWidgetSnapshot() }
      .onChange(of: model.isRestoring) { _, _ in model.scheduleWidgetSnapshot() }
  }
}
