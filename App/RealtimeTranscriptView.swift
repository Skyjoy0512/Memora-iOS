import SwiftUI

/// The live transcription shown in the recording sheet. Settled lines read
/// normally; the line still being recognised is lighter. When nothing can run,
/// it says why instead of showing an empty box.
struct RealtimeTranscriptView: View {
  var service: RealtimeTranscriptionService

  var body: some View {
    if service.finalized.isEmpty, service.volatileText.isEmpty {
      VStack(spacing: 10) {
        Image(icon: .textBubble)
          .font(.title2)
          .foregroundStyle(.secondary)
        Text(service.unavailableReason ?? "録音を終えると文字起こしします")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.horizontal, 20)
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(service.finalized.enumerated()), id: \.offset) { _, line in
              Text(line)
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
        .onChange(of: service.finalized.count) { _, _ in
          withAnimation(.smooth(duration: 0.2)) {
            proxy.scrollTo("liveBottom", anchor: .bottom)
          }
        }
      }
    }
  }
}
