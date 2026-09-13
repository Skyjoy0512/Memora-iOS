import SwiftUI

struct CaptureSessionView: View {
  @Environment(MemoraModel.self) private var model
  @State private var stopFeedback = 0

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Spacer()

        VStack(spacing: 16) {
          Text("録音中")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.red)

          Text(MemoraFormat.duration(model.recordingElapsed))
            .font(.system(size: 54, weight: .medium, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())

          RecordingWaveform()
            .frame(height: 96)
            .padding(.horizontal, 24)
            .accessibilityHidden(true)
        }

        Spacer()

        VStack(spacing: 24) {
          Label("このiPhoneに保存しています", systemImage: "lock.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)

          Button {
            stopFeedback += 1
            Task {
              await model.stopCapture()
            }
          } label: {
            ZStack {
              Circle()
                .fill(.red)
                .frame(width: 92, height: 92)
              RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white)
                .frame(width: 30, height: 30)
            }
          }
          .buttonStyle(.plain)
          .accessibilityLabel("録音を停止")

          Text("停止すると文字起こしとAI整理が始まります")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.bottom, 16)
      }
      .padding(.horizontal, 20)
      .background(Color(uiColor: .systemBackground))
      .navigationTitle("新しい会話")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("録音画面を閉じる", systemImage: "chevron.down") {
            model.isCapturePresented = false
          }
          .labelStyle(.iconOnly)
        }
      }
    }
    .sensoryFeedback(.impact(weight: .heavy), trigger: stopFeedback)
    .interactiveDismissDisabled()
  }
}

private struct RecordingWaveform: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let barCount = 24

  var body: some View {
    if reduceMotion {
      bars(at: 0)
    } else {
      TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { context in
        bars(at: context.date.timeIntervalSinceReferenceDate)
      }
    }
  }

  private func bars(at time: TimeInterval) -> some View {
    HStack(spacing: 4) {
      ForEach(0..<barCount, id: \.self) { index in
        Capsule()
          .fill(.primary.opacity(0.78))
          .frame(maxWidth: .infinity)
          .frame(height: height(index: index, time: time))
      }
    }
  }

  /// Two out-of-step waves so the shape reads as speech rather than a pulse.
  private func height(index: Int, time: TimeInterval) -> CGFloat {
    let offset = Double(index) * 0.55
    let wave = abs(sin(time * 2.1 + offset)) * 0.7 + abs(sin(time * 1.3 + offset * 1.7)) * 0.3
    return 14 + wave * 70
  }
}
