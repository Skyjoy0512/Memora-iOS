import Foundation
import WidgetKit

actor WidgetSnapshotPublisher {
  static let shared = WidgetSnapshotPublisher()

  func publish(_ snapshot: MemoraWidgetSnapshot?) {
    do {
      if let snapshot { try MemoraWidgetSnapshotStore.write(snapshot) }
      else { try MemoraWidgetSnapshotStore.clear() }
      WidgetCenter.shared.reloadTimelines(ofKind: "app.bitrig.memora.today")
      WidgetCenter.shared.reloadTimelines(ofKind: "app.bitrig.memora.project")
    } catch {
      // A failed publish must not keep a previously shared private snapshot.
      try? MemoraWidgetSnapshotStore.clear()
      WidgetCenter.shared.reloadAllTimelines()
    }
  }
}
