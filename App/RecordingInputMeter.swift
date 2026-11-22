import SwiftUI

/// Render microphone input without invalidating the rest of the recording sheet.
struct RecordingInputMeter: View {
  @Environment(MemoraModel.self) private var model

  var body: some View {
    Capsule()
      .fill(MemoraPalette.selection)
      .frame(width: 52, height: 3)
      .overlay(alignment: .leading) {
        Capsule()
          .fill(.secondary)
          .frame(width: 52 * model.levelMeter.level)
      }
      .accessibilityHidden(true)
  }
}
