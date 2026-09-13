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

          RecordingWaveform(elapsed: model.recordingElapsed)
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
  var elapsed: TimeInterval

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<24, id: \.self) { index in
        let phase = elapsed + Double(index) * 0.67
        let height = 14 + abs(sin(phase)) * 70
        Capsule()
          .fill(index.isMultiple(of: 5) ? Color.red : Color.primary.opacity(0.76))
          .frame(maxWidth: .infinity)
          .frame(height: height)
      }
    }
  }
}
