import SwiftUI

/// Ask AI presents its attachment choices without replacing the native editor.
struct AIComposerAttachmentButton: View {
  var offersMentions: Bool
  var usesChatSheet = false
  var onPresentChatSheet: (() -> Void)?
  var onOpen: () -> Void
  var onSelect: (AIComposerAttachmentAction) -> Void

  var body: some View {
    let actions = AIComposerAttachmentAction.allCases.filter { $0 != .camera && (offersMentions || $0 != .mention) }
    if usesChatSheet {
      Button {
        onOpen()
        onPresentChatSheet?()
      } label: {
        attachmentIcon
      }
      .buttonStyle(.plain)
      .accessibilityLabel("チャットに追加")
      .accessibilityHint("添付とWeb検索のメニューを開きます")
      .accessibilityIdentifier("ai.composer.add")
    } else {
      Menu {
        ForEach(actions) { action in
          Button {
            onOpen()
            onSelect(action)
          } label: {
            Label(action.title, icon: action.icon)
          }
        }
      } label: {
        attachmentIcon
      }
      .buttonStyle(.plain)
      .accessibilityLabel("添付を追加")
      .accessibilityHint(offersMentions ? "写真、ファイル、音声の添付やメンションを選びます" : "写真、ファイル、音声を添付します")
      .simultaneousGesture(TapGesture().onEnded { onOpen() })
    }
  }

  private var attachmentIcon: some View {
    Image(icon: .paperclip, size: 20)
      .frame(width: 36, height: 36)
      .background(MemoraPalette.card, in: Circle())
      .frame(width: 44, height: 44)
      .contentShape(Circle())
      .accessibilityHidden(true)
  }
}
