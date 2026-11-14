import SwiftUI

/// The system menu owns the glass presentation; the composer never morphs.
struct AIComposerAttachmentButton: View {
  var offersMentions: Bool
  var onOpen: () -> Void
  var onSelect: (AIComposerAttachmentAction) -> Void

  var body: some View {
    let actions = AIComposerAttachmentAction.allCases.filter { offersMentions || $0 != .mention }
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
