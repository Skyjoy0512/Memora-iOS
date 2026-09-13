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

          SiriWaveView()
            .frame(height: 118)
            .padding(.horizontal, 8)
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
      .overlay {
        RecordingBottomBeam()
      }
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
