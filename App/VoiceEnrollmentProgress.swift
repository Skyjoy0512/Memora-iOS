import SwiftUI

struct VoiceEnrollmentProgress: View {
  var enrollment: VoiceEnrollmentService

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      LabeledContent("録音中", value: "\(Int(enrollment.duration)) / 40秒")
        .monospacedDigit()
        .accessibilityValue("\(Int(enrollment.duration))秒録音しました")
      ProgressView(value: enrollment.level)
        .accessibilityLabel("マイクの音量")
    }
  }
}
