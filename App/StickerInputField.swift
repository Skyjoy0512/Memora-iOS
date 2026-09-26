import SwiftUI
import UIKit

/// An invisible text field that opens the emoji keyboard, where Memoji
/// stickers live. There is no Memoji picker API; a sticker inserted into a
/// field that accepts adaptive image glyphs arrives as an image, and a plain
/// emoji is drawn into one, so either becomes the avatar.
struct StickerInputField: UIViewRepresentable {
  @Binding var isActive: Bool
  var onPick: (UIImage) -> Void

  func makeUIView(context: Context) -> EmojiTextView {
    let view = EmojiTextView()
    view.supportsAdaptiveImageGlyph = true
    view.backgroundColor = .clear
    view.textColor = .clear
    view.tintColor = .clear
    view.delegate = context.coordinator
    view.accessibilityElementsHidden = true
    return view
  }

  func updateUIView(_ view: EmojiTextView, context: Context) {
    context.coordinator.parent = self
    if isActive, !view.isFirstResponder {
      view.becomeFirstResponder()
    } else if !isActive, view.isFirstResponder {
      view.resignFirstResponder()
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  final class Coordinator: NSObject, UITextViewDelegate {
    var parent: StickerInputField

    init(parent: StickerInputField) {
      self.parent = parent
    }

    func textViewDidChange(_ textView: UITextView) {
      let text = textView.attributedText ?? NSAttributedString()
      defer { textView.attributedText = NSAttributedString() }
      guard text.length > 0 else { return }

      var sticker: UIImage?
      text.enumerateAttribute(.adaptiveImageGlyph, in: NSRange(location: 0, length: text.length)) { value, _, stop in
        if let glyph = value as? NSAdaptiveImageGlyph, let image = UIImage(data: glyph.imageContent) {
          sticker = image
          stop.pointee = true
        }
      }

      if let sticker {
        parent.onPick(sticker)
      } else if let emoji = text.string.last(where: { $0.isEmojiPresentation }) {
        parent.onPick(Self.render(emoji))
      }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
      if parent.isActive {
        parent.isActive = false
      }
    }

    /// Draws one emoji large enough for the Settings header.
    private static func render(_ emoji: Character) -> UIImage {
      let side: CGFloat = 512
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = false
      return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
        let string = NSAttributedString(
          string: String(emoji),
          attributes: [.font: UIFont.systemFont(ofSize: side * 0.78)]
        )
        let bounds = string.boundingRect(
          with: CGSize(width: side, height: side),
          options: [.usesLineFragmentOrigin],
          context: nil
        )
        string.draw(at: CGPoint(x: (side - bounds.width) / 2, y: (side - bounds.height) / 2))
      }
    }
  }
}

private extension Character {
  /// True for characters drawn as emoji by default, so digits and letters
  /// typed from another keyboard are not mistaken for one.
  var isEmojiPresentation: Bool {
    unicodeScalars.contains { $0.properties.isEmojiPresentation }
      || (unicodeScalars.count > 1 && unicodeScalars.contains { $0.properties.isEmoji })
  }
}
