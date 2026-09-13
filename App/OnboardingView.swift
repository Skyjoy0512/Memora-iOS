import SwiftUI

struct OnboardingView: View {
  var startRecording: () -> Void
  var showSample: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Spacer(minLength: 44)

      Image(systemName: "waveform")
        .font(.system(size: 36, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 72, height: 72)
        .background(.indigo, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)

      Text("話せば、\n次にすることまで残る。")
        .font(.largeTitle.bold())
        .tracking(-0.8)
        .padding(.top, 28)

      Text("Memoraは会話を録音し、要点・決定・タスクへ自動で整理します。")
        .font(.title3)
        .foregroundStyle(.secondary)
        .padding(.top, 14)

      HStack(spacing: 0) {
        JourneyStep(symbol: "waveform", title: "記録")
        JourneyConnector()
        JourneyStep(symbol: "text.alignleft", title: "理解")
        JourneyConnector()
        JourneyStep(symbol: "checkmark", title: "行動")
      }
      .padding(.vertical, 38)

      Spacer(minLength: 20)

      VStack(spacing: 12) {
        Button(action: startRecording) {
          Label("最初の会話を録音", systemImage: "record.circle")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(.indigo, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)

        Button("サンプルで見る", action: showSample)
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 10)
      }

      Label("録音はまず、このiPhoneに保存されます", systemImage: "lock.shield")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }
    .padding(.horizontal, 24)
    .background(Color(uiColor: .systemBackground))
  }
}

private struct JourneyStep: View {
  var symbol: String
  var title: String

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: symbol)
        .font(.body.weight(.semibold))
        .foregroundStyle(.indigo)
        .frame(width: 42, height: 42)
        .background(.indigo.opacity(0.1), in: Circle())
      Text(title)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }
  }
}

private struct JourneyConnector: View {
  var body: some View {
    Rectangle()
      .fill(.tertiary)
      .frame(height: 1)
      .frame(maxWidth: .infinity)
      .offset(y: -12)
      .accessibilityHidden(true)
  }
}
