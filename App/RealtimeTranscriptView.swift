import SwiftUI

/// The live transcription shown in the recording sheet. Settled lines read
/// normally; the line still being recognised is lighter. When nothing can run,
/// it says why instead of showing an empty box.
struct RealtimeTranscriptView: View {
  var service: RealtimeTranscriptionService
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    if service.history.lines.isEmpty, service.volatileText.isEmpty {
      VStack(spacing: 10) {
        Image(icon: .textBubble, size: 22)
          .foregroundStyle(.primary)
        Text(service.unavailableReason ?? "録音を終えると文字起こしします")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.horizontal, MemoraSpacing.xl)
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            if service.history.hasTrimmedHistory {
              Text("ライブ表示は直近200文、長い発言は末尾のみです。全文は保存した音声から文字起こしします。")
                .font(.caption).foregroundStyle(.secondary)
            }
            if let reason = service.unavailableReason {
              Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(service.history.lines) { line in
              Text(line.text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !service.volatileText.isEmpty {
              Text(service.volatileText)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Color.clear
              .frame(height: 1)
              .id("liveBottom")
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: service.history.totalLines) { _, _ in
          withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) {
            proxy.scrollTo("liveBottom", anchor: .bottom)
          }
        }
      }
    }
  }
}
