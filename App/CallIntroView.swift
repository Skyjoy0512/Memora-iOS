import SwiftUI

/// The first screen of call setup: a picture of a call being noted, and what
/// it takes to start.
struct CallIntroView: View {
  var onStart: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      CallIllustration()
        .padding(.horizontal, MemoraSpacing.page)
        .padding(.top, MemoraSpacing.md)
        .frame(maxHeight: .infinity)

      VStack(spacing: 14) {
        Text("電話の内容を\nMemoraでメモする")
          .font(.title.bold())
          .multilineTextAlignment(.center)
        Text("Memoraからかけた電話は、相手の声も含めて録音し、端末内で文字起こしと要約をします。最初に一度だけ、電話番号の確認をします。")
          .font(.body)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding(.horizontal, MemoraSpacing.section)
      .padding(.vertical, MemoraSpacing.xxl)

      CallPrimaryButton(title: "はじめる", action: onStart)
        .padding(.horizontal, MemoraSpacing.xxl)
        .padding(.bottom, MemoraSpacing.lg)
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .navigationBarTitleDisplayMode(.inline)
  }
}

/// A drawing of a call in Memora: notes above, the call controls below.
private struct CallIllustration: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 10) {
        Capsule().fill(.quaternary).frame(width: 36, height: 4).frame(maxWidth: .infinity)
        Text("田中さんとの通話")
          .font(.title3.bold())
        Label("メモを自由にどうぞ…", icon: .pencil)
          .font(.footnote)
          .foregroundStyle(.secondary)
        Spacer(minLength: 40)
        Text("通話の録音には、相手への告知と同意が必要な場合があります。")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .padding(MemoraSpacing.md)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: MemoraRadius.field, style: .continuous))
      }
      .padding(MemoraSpacing.lg)

      VStack(spacing: 12) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("+81 90-1234-5678").font(.caption.weight(.semibold))
            Text("00:12").font(.caption2).opacity(0.7)
          }
          Spacer()
          ForEach([MemoraIcon.circleGrid3x3Fill, .mic, .speakerWave2Fill], id: \.self) { icon in
            Image(icon: icon)
              .font(.caption)
              .frame(width: 30, height: 30)
              .background(.white.opacity(0.12), in: Circle())
          }
        }
        HStack {
          Image(icon: .pauseFill)
            .font(.caption)
            .frame(width: 52, height: 30)
            .background(.white.opacity(0.12), in: Capsule())
          Spacer()
          Label("00:12", icon: .waveform)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.green)
          Spacer()
          Image(icon: .phoneDownFill)
            .font(.caption)
            .frame(width: 52, height: 30)
            .background(.red, in: Capsule())
        }
      }
      .foregroundStyle(.white)
      .padding(MemoraSpacing.lg)
      .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: MemoraRadius.card, style: .continuous))
      .padding(MemoraSpacing.sm)
    }
    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    .padding(MemoraSpacing.sm)
    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 42, style: .continuous))
    .accessibilityHidden(true)
  }
}
