import SwiftUI

/// The percentage comes from authorized current tasks, never a generated value.
struct AIInterfaceTaskProgress: View {
  var tasks: [MemoraTask]

  var body: some View {
    let completed = tasks.filter(\.isCompleted).count
    VStack(alignment: .leading, spacing: 8) {
      Text("\(tasks.count)件中\(completed)件が完了").font(.subheadline)
      if !tasks.isEmpty {
        ProgressView(value: Double(completed), total: Double(tasks.count))
          .tint(MemoraPalette.textPrimary)
          .accessibilityLabel("タスクの完了状況")
          .accessibilityValue("\(tasks.count)件中\(completed)件が完了")
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}
