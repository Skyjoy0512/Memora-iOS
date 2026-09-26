import SwiftUI

/// The color behind a Memoji or emoji avatar. Soft tones, as on Contacts
/// posters, so the sticker stays the focus.
enum AvatarBackground: String, CaseIterable, Identifiable {
  case sky
  case mint
  case lemon
  case peach
  case rose
  case lavender
  case graphite

  var id: Self { self }

  var label: String {
    switch self {
    case .sky: "空色"
    case .mint: "ミント"
    case .lemon: "レモン"
    case .peach: "ピーチ"
    case .rose: "ローズ"
    case .lavender: "ラベンダー"
    case .graphite: "グラファイト"
    }
  }

  var gradient: LinearGradient {
    let colors: [Color] = switch self {
    case .sky: [Color(red: 0.62, green: 0.82, blue: 1.0), Color(red: 0.38, green: 0.62, blue: 0.98)]
    case .mint: [Color(red: 0.66, green: 0.93, blue: 0.82), Color(red: 0.33, green: 0.78, blue: 0.64)]
    case .lemon: [Color(red: 1.0, green: 0.93, blue: 0.6), Color(red: 0.99, green: 0.8, blue: 0.32)]
    case .peach: [Color(red: 1.0, green: 0.8, blue: 0.66), Color(red: 0.98, green: 0.6, blue: 0.45)]
    case .rose: [Color(red: 1.0, green: 0.74, blue: 0.82), Color(red: 0.94, green: 0.47, blue: 0.62)]
    case .lavender: [Color(red: 0.84, green: 0.78, blue: 1.0), Color(red: 0.6, green: 0.5, blue: 0.95)]
    case .graphite: [Color(red: 0.62, green: 0.64, blue: 0.68), Color(red: 0.36, green: 0.38, blue: 0.42)]
    }
    return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
  }
}
