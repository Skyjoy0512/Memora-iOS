import SwiftUI

/// The answer as a shareable card: the real question and answer, with the
/// time they were written, so a screenshot becomes something worth keeping.
struct AIAnswerShareCard: View {
  var content: AIAnswerShareContent
  var width: CGFloat = 360

  private var height: CGFloat { (width * 1.22).rounded() }

  private var dateText: String {
    content.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened)
      .locale(Locale(identifier: "ja_JP")))
  }

  private var excerpt: AttributedString {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: content.answer, options: options))
      ?? AttributedString(content.answer)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: MemoraSpacing.lg) {
      Text(content.question.isEmpty ? "Memoraの回答" : content.question)
        .font(.footnote.weight(.medium))
        .foregroundStyle(Color.black.opacity(0.5))
        .lineLimit(2)

      Text(excerpt)
        .font(.system(size: 15))
        .lineSpacing(5)
        .foregroundStyle(Color.black.opacity(0.86))
        .lineLimit(12)
        .frame(maxWidth: .infinity, alignment: .leading)

      Spacer(minLength: 0)

      VStack(alignment: .leading, spacing: MemoraSpacing.xs) {
        MemoraWordmark(width: 60, color: .black)
        Text(dateText)
          .font(.system(size: 10))
          .foregroundStyle(Color.black.opacity(0.4))
      }
    }
    .padding(22)
    .frame(width: width, height: height, alignment: .topLeading)
    .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    .padding(14)
    .background(gradient, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
  }

  /// A quiet blue wash around the card, close enough to the app's accent to
  /// read as Memora in another app's timeline.
  private var gradient: LinearGradient {
    LinearGradient(colors: [
      Color(red: 0.74, green: 0.85, blue: 1),
      Color(red: 0.88, green: 0.90, blue: 1),
      Color(red: 1, green: 0.94, blue: 0.90)
    ], startPoint: .topLeading, endPoint: .bottomTrailing)
  }
}
