import AppIntents
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 18.0, *)
struct MemoraRecordControl: ControlWidget {
  static var kind = "app.bitrig.memora.record-control"

  var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind) {
      ControlWidgetButton(action: OpenMemoraIntent()) {
        Label("Memoraを開く", icon: .waveform)
      }
    }
    .displayName("Memoraを開く")
    .description("アプリを開きます。録音はアプリ内で開始してください。")
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
