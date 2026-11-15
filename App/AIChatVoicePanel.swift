import SwiftUI

struct AIChatVoicePanel: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  var speechInput: SpeechInputService
  var status: String
  var transcript: String
  var modelName: String
  var attachmentName: String?
  var onRemoveAttachment: () -> Void
  var isResponding: Bool
  var isSpeaking: Bool
  @Binding var isSpeakerEnabled: Bool
  var onAttach: () -> Void
  var onModel: () -> Void
  var onMicrophone: () -> Void
  var onStop: () -> Void
  var onClose: () -> Void

  var body: some View {
    VStack(spacing: 20) {
      Text(status).font(.subheadline).foregroundStyle(.secondary)
        .accessibilityAddTraits(.updatesFrequently)
      if !transcript.isEmpty {
        Text(transcript).font(.body).lineLimit(3).multilineTextAlignment(.center)
          .frame(maxWidth: 480)
      }
      if let attachmentName {
        HStack(spacing: 8) {
          Label(attachmentName, icon: .paperclip).font(.caption).lineLimit(1)
          Button("添付を外す", icon: .xmark, action: onRemoveAttachment)
            .labelStyle(.iconOnly).frame(width: 44, height: 44)
        }
        .padding(.leading, 12)
        .background(MemoraPalette.card, in: Capsule())
      }
      Spacer(minLength: 8)
      Button(action: onMicrophone) {
        Image(icon: isSpeaking || isResponding ? .stopFill : .mic, size: 32)
          .frame(width: 64, height: 64)
          .memoraGlass(in: Circle(), interactive: true, backed: false)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(isResponding ? "回答を停止" : isSpeaking ? "読み上げを停止" : speechInput.isListening ? "音声入力を終えて送信" : "話し始める")
      .accessibilityHint("入力した音声を、選択中のAIに送信します")
      Spacer(minLength: 8)
      HStack(spacing: 8) {
        voiceButton("チャットに追加", icon: .plus, action: onAttach)
        Button(action: onModel) {
          HStack(spacing: 8) {
            Text(modelName).font(.subheadline).lineLimit(1)
            Image(icon: .chevronDown, size: 14)
          }
          .padding(.horizontal, 16).frame(minHeight: 44)
          .memoraGlass(in: Capsule(), interactive: true, backed: false)
          .contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityLabel("モデルを選択、\(modelName)")
        Spacer(minLength: 0)
        if isSpeaking { voiceButton("読み上げを停止", icon: .stopFill, action: onStop) }
        Toggle(isOn: $isSpeakerEnabled) {
          Image(icon: .speakerWave2Fill, size: 21)
            .overlay {
              if !isSpeakerEnabled {
                Rectangle().frame(width: 26, height: 2).rotationEffect(.degrees(-45))
              }
            }
            .frame(width: 44, height: 44)
            .memoraGlass(in: Circle(), interactive: true, backed: false)
            .contentShape(Circle())
        }
        .toggleStyle(.button).buttonStyle(.plain)
        .accessibilityLabel("回答を読み上げる")
        voiceButton("音声会話を閉じる", icon: .xmark, isPrimary: true, action: onClose)
      }
    }
    .padding(.horizontal, 8).padding(.top, 30).padding(.bottom, 8)
    .frame(maxWidth: .infinity)
    .frame(height: typeSize.isAccessibilitySize ? 400 : 300)
    .background {
      LinearGradient(colors: [MemoraPalette.background.opacity(0), Color.cyan.opacity(0.12), Color.blue.opacity(0.3)], startPoint: .top, endPoint: .bottom)
        .padding(.horizontal, -12).ignoresSafeArea(edges: .bottom)
    }
  }

  private func voiceButton(_ title: String, icon: MemoraIcon, isPrimary: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(icon: icon, size: 23)
        .foregroundStyle(isPrimary ? MemoraPalette.actionLabel : MemoraPalette.textPrimary)
        .frame(width: 44, height: 44)
        .background(isPrimary ? MemoraPalette.action : .clear, in: Circle())
        .memoraGlass(in: Circle(), interactive: true, backed: false)
        .contentShape(Circle())
    }.buttonStyle(.plain).accessibilityLabel(title)
  }
}
