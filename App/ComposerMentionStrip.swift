import SwiftUI

struct ComposerMentionStrip: View {
  var mentions: [ComposerMention]
  var remove: (ComposerMention) -> Void

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(mentions) { mention in
          Button { remove(mention) } label: {
            HStack(spacing: 6) {
              Text("@" + mention.label).lineLimit(1)
              Image(icon: .xmark)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(MemoraPalette.secondaryBackground, in: Capsule())
            .contentShape(Capsule())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("\(mention.label)の指定を削除")
          .accessibilityHint("別の対象に変えるには、削除して@を入力してください。")
        }
      }
    }
    .scrollIndicators(.hidden)
    .scrollDismissesKeyboard(.never)
  }
}
