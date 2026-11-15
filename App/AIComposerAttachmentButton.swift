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
        Image(icon: .plus, size: 22)
          .frame(width: 36, height: 36)
          .background(MemoraPalette.card, in: Circle())
          .frame(width: 44, height: 44).contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("チャットに追加")
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
        ToolbarActionLabel("添付を追加", icon: .paperclip)
          .environment(\.memoraToolbarControlSize, MemoraSpacing.touchTarget)
      }
      .buttonStyle(.plain)
      .frame(width: MemoraSpacing.touchTarget, height: MemoraSpacing.touchTarget)
      .accessibilityLabel("添付を追加")
      .accessibilityHint("ファイルの添付やプラグイン・スキル・ソースの指定")
      .simultaneousGesture(TapGesture().onEnded { onOpen() })
    }
  }
}
