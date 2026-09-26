import AppIntents
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 18.0, *)
struct MemoraRecordControl: ControlWidget {
  static var kind = "app.bitrig.memora.record-control"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind) {
      ControlWidgetButton(action: OpenMemoraIntent()) {
        Label("録音", icon: .waveform)
      }
    }
    .displayName("Memoraで録音")
    .description("Memoraを開いて会話の記録を始めます。")
  }
}

@available(iOSApplicationExtension 18.0, *)
private struct OpenMemoraIntent: AppIntent {
  static var title: LocalizedStringResource = "Memoraを開く"
  static var openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    .result()
  }
}
