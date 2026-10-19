import SwiftUI

/// A call in progress: notes on top, the call's controls below, and the
/// reminder about consent to record.
struct ActiveCallView: View {
  @Bindable var session: PhoneCallSession
  var onEnd: () -> Void
  @State private var isKeypadShown = false
  @FocusState private var isNotesFocused: Bool

  var body: some View {
    VStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 10) {
        Text(session.title)
          .font(.title2.bold())
        TextField("メモを自由にどうぞ…", text: $session.notes, axis: .vertical)
          .focused($isNotesFocused)
          .frame(maxHeight: .infinity, alignment: .topLeading)
      }
      .padding(MemoraSpacing.xl)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

      Label("通話の録音には、相手への告知と同意が必要な場合があります。録音は一時停止できます。", icon: .bellFill)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(MemoraSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
        .padding(.horizontal, MemoraSpacing.md)

      controls
        .padding(.horizontal, MemoraSpacing.sm)
        .padding(.bottom, MemoraSpacing.sm)
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .sheet(isPresented: $isKeypadShown) {
      CallKeypadSheet { digit in session.onDigit(digit) }
        .presentationDetents([.medium])
    }
  }

  private var controls: some View {
    VStack(spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text(session.contactName ?? PhoneNumberFormat.display(session.number))
            .font(.subheadline.weight(.semibold))
          CallElapsedText(startedAt: session.startedAt)
            .font(.caption.monospacedDigit())
            .opacity(0.7)
        }
        Spacer()
        roundButton(.circleGrid3x3Fill, label: "キーパッド", isOn: false) { isKeypadShown = true }
        roundButton(session.isMuted ? .micSlash : .mic, label: session.isMuted ? "ミュート解除" : "ミュート", isOn: session.isMuted) {
          session.isMuted.toggle()
          session.onMuteChange(session.isMuted)
        }
        roundButton(.speakerWave2Fill, label: "スピーカー", isOn: session.isSpeakerOn) {
          session.isSpeakerOn.toggle()
          session.onSpeakerChange(session.isSpeakerOn)
        }
      }

      HStack {
        Button {
          session.isRecording.toggle()
          session.onRecordingChange(session.isRecording)
        } label: {
          Image(icon: session.isRecording ? .pauseFill : .waveform)
            .frame(width: 64, height: 40)
            .background(.white.opacity(0.14), in: Capsule())
        }
        .accessibilityLabel(session.isRecording ? "録音を一時停止" : "録音を再開")

        Spacer()
        Label(session.isRecording ? "録音中" : "一時停止中", icon: .waveform)
          .font(.caption.weight(.semibold))
          .foregroundStyle(session.isRecording ? .green : .white.opacity(0.6))
        Spacer()

        Button {
          session.onHangUp()
          onEnd()
        } label: {
          Image(icon: .phoneDownFill)
            .frame(width: 64, height: 40)
            .background(.red, in: Capsule())
        }
        .accessibilityLabel("通話を終える")
      }
    }
    .buttonStyle(.plain)
    .foregroundStyle(.white)
    .padding(MemoraSpacing.lg)
    .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: MemoraRadius.bubble, style: .continuous))
  }

  private func roundButton(_ icon: MemoraIcon, label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(icon: icon)
        .frame(width: 40, height: 40)
        .background(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.14)), in: Circle())
        .foregroundStyle(isOn ? .black : .white)
    }
    .accessibilityLabel(label)
    .accessibilityAddTraits(isOn ? .isSelected : [])
  }
}

/// The call's running time, in a leaf of its own so the ticking does not
/// redraw the notes.
private struct CallElapsedText: View {
  var startedAt: Date?

  var body: some View {
    if let startedAt {
      Text(startedAt, style: .timer)
    } else {
      Text("呼び出し中…")
    }
  }
}
