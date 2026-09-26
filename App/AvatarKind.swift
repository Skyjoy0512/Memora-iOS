import Foundation

/// What the profile picture is. A photo fills the circle; a Memoji or emoji
/// sticker sits on a colored background, like a contact card.
enum AvatarKind: String {
  case none
  case photo
  case sticker
}
