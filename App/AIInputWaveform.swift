import SwiftUI

/// Only this leaf observes microphone levels; the conversation stays still.
struct AIInputWaveform: View {
  var speechInput: SpeechInputService
  @State private var levels = Array(repeating: 0.0, count: 44)

  var body: some View {
    GeometryReader { geometry in
      HStack(spacing: 3) {
        ForEach(levels.indices, id: \.self) { index in
          Capsule()
            .fill(MemoraPalette.textPrimary)
            .frame(width: max(2, (geometry.size.width - 129) / 44), height: 3 + levels[index] * 25)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(height: 32)
    .onChange(of: speechInput.audioLevel) { _, level in
      levels.removeFirst()
      levels.append(level)
    }
    .accessibilityLabel(speechInput.isListening ? "音声を入力中" : "音声入力を停止中")
  }
}
