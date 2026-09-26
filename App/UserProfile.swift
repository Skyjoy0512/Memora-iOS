import Observation
import UIKit

/// The person's own picture and name, shown on Settings and the top-right
/// button of every tab. It is local to this iPhone and not an account: the
/// picture is a file in the app's container and only its kind, background, and
/// the name are settings.
@MainActor
@Observable
final class UserProfile {
  private(set) var avatar: UIImage?
  private(set) var avatarKind: AvatarKind
  var background: AvatarBackground {
    didSet { UserDefaults.standard.set(background.rawValue, forKey: Key.background) }
  }
  var name: String {
    didSet { UserDefaults.standard.set(name, forKey: Key.name) }
  }

  /// The longest side a stored avatar keeps. Large enough for the Settings
  /// header at 3x, small enough to decode instantly.
  private static let maxSide: CGFloat = 600

  private enum Key {
    static let kind = "memora.profile.avatarKind"
    static let background = "memora.profile.background"
    static let name = "memora.profile.name"
  }

  private static var folder: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Profile", isDirectory: true)
  }

  private static var avatarURL: URL {
    folder.appendingPathComponent("avatar.png")
  }

  /// The uncropped photo behind a photo avatar, so editing again can widen the
  /// crop instead of only narrowing the last one.
  private static var sourceURL: URL {
    folder.appendingPathComponent("avatar-source.jpg")
  }

  init() {
    let defaults = UserDefaults.standard
    name = defaults.string(forKey: Key.name) ?? ""
    background = AvatarBackground(rawValue: defaults.string(forKey: Key.background) ?? "") ?? .sky
    let kind = AvatarKind(rawValue: defaults.string(forKey: Key.kind) ?? "") ?? .none
    let image = kind == .none ? nil : UIImage(contentsOfFile: Self.avatarURL.path)
    avatar = image
    // A missing file means there is nothing to show, whatever the setting says.
    avatarKind = image == nil ? .none : kind
  }

  /// Stores a new picture, replacing the previous one. Returns false when it
  /// could not be written, so the editor can say so instead of closing.
  @discardableResult
  func setAvatar(_ image: UIImage, kind: AvatarKind, sourcePhoto: Data? = nil) -> Bool {
    let scaled = image.fitted(maxSide: Self.maxSide)
    guard let data = scaled.pngData() else { return false }
    do {
      try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
      try data.write(to: Self.avatarURL, options: [.atomic, .completeFileProtection])
      if let sourcePhoto {
        try sourcePhoto.write(to: Self.sourceURL, options: [.atomic, .completeFileProtection])
      } else if kind != .photo {
        try? FileManager.default.removeItem(at: Self.sourceURL)
      }
    } catch {
      return false
    }
    avatar = scaled
    avatarKind = kind
    UserDefaults.standard.set(kind.rawValue, forKey: Key.kind)
    return true
  }

  /// The photo the current avatar was cropped from, when there is one.
  func sourcePhoto() -> Data? {
    guard avatarKind == .photo else { return nil }
    return try? Data(contentsOf: Self.sourceURL)
  }

  func removeAvatar() {
    try? FileManager.default.removeItem(at: Self.avatarURL)
    try? FileManager.default.removeItem(at: Self.sourceURL)
    avatar = nil
    avatarKind = .none
    UserDefaults.standard.set(AvatarKind.none.rawValue, forKey: Key.kind)
  }
}

private extension UIImage {
  /// A copy no larger than `maxSide`, keeping transparency so a Memoji keeps
  /// its chosen background behind it.
  func fitted(maxSide: CGFloat) -> UIImage {
    let longest = max(size.width, size.height)
    guard longest > maxSide else { return self }
    let factor = maxSide / longest
    let target = CGSize(width: size.width * factor, height: size.height * factor)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in
      draw(in: CGRect(origin: .zero, size: target))
    }
  }
}
