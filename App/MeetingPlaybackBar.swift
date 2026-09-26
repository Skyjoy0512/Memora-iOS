import SwiftUI

/// The recording's transport, shown under the meeting once playback has been
/// started from the toolbar. It gathers position, seeking, skipping and speed in
/// one place so the transcript's highlight can follow along.
struct MeetingPlaybackBar: View {
  @Environment(MemoraModel.self) private var model
  var player: AudioPlayerService

  /// Held while the finger is on the slider, so the label follows the drag
  /// instead of the ticker pulling it back.
  @State private var scrubValue: TimeInterval = 0
  @State private var isScrubbing = false

  private static let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 2]

  var body: some View {
    VStack(spacing: 8) {
      positionSlider
      transportRow

      if model.isRecording {
        Text("録音中は再生できません")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .memoraGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    .accessibilityElement(children: .contain)
  }

  private var positionSlider: some View {
    VStack(spacing: 2) {
      Slider(
        value: sliderValue,
        in: 0...max(player.duration, 0.01),
        onEditingChanged: { editing in
          if editing {
            scrubValue = player.currentTime
            isScrubbing = true
          } else {
            isScrubbing = false
            player.seek(to: scrubValue)
          }
        }
      )
      .disabled(model.isRecording || player.duration <= 0)
      .accessibilityLabel("再生位置")
      .accessibilityValue(MemoraFormat.duration(player.currentTime))

      HStack {
        Text(MemoraFormat.duration(displayedTime))
        Spacer()
        Text("-" + MemoraFormat.duration(max(0, player.duration - displayedTime)))
      }
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)
      .accessibilityHidden(true)
    }
  }

  private var transportRow: some View {
    HStack(spacing: 28) {
      Button("15秒戻す", systemImage: "gobackward.15") {
        player.skip(by: -15)
      }
      .labelStyle(.iconOnly)

      Button(player.isPlaying ? "一時停止" : "再生", systemImage: player.isPlaying ? "pause.fill" : "play.fill") {
        player.toggle()
      }
      .labelStyle(.iconOnly)
      .font(.title2)

      Button("15秒送る", systemImage: "goforward.15") {
        player.skip(by: 15)
      }
      .labelStyle(.iconOnly)

      Spacer(minLength: 0)

      Picker("再生速度", selection: rateBinding) {
        ForEach(Self.rates, id: \.self) { rate in
          Text(rateLabel(rate)).tag(rate)
        }
      }
      .pickerStyle(.menu)
      .accessibilityLabel("再生速度")
    }
    .font(.title3)
    .buttonStyle(.plain)
    .disabled(model.isRecording)
    .foregroundStyle(model.isRecording ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
  }

  private var displayedTime: TimeInterval {
    isScrubbing ? scrubValue : player.currentTime
  }

  private var sliderValue: Binding<Double> {
    Binding(
      get: { isScrubbing ? scrubValue : player.currentTime },
      set: { value in
        scrubValue = value
        // VoiceOver's increment and decrement change the value without starting
        // an editing session, so they must seek here to take effect.
        if !isScrubbing {
          player.seek(to: value)
        }
      }
    )
  }

  private var rateBinding: Binding<Float> {
    Binding(
      get: { player.rate },
      set: { player.rate = $0 }
    )
  }

  private func rateLabel(_ rate: Float) -> String {
    let number = rate == rate.rounded() ? String(Int(rate)) : String(format: "%g", rate)
    return "\(number)倍"
  }
}
