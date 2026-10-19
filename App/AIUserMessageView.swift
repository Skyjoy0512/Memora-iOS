import SwiftUI
import UIKit

struct AIUserMessageView: View {
  var text: String
  var attachmentName: String?
  var restoreInput: (() -> Void)?

  var body: some View {
    HStack {
      Spacer(minLength: 44)
      VStack(alignment: .leading, spacing: 8) {
        Text(text).font(MemoraTypography.body).textSelection(.enabled)
        if let attachmentName {
          Label(attachmentName, icon: .paperclip)
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .aiBubble()
      .contextMenu {
        Button("コピー", icon: .docOnDoc) { UIPasteboard.general.string = text }
        if let restoreInput {
          Button("入力欄に戻す", icon: .arrowUturnBackward, action: restoreInput)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("あなた: \(text)" + (attachmentName.map { "、添付: " + $0 } ?? ""))
  }
}
