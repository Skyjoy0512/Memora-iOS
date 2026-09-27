import SwiftUI

/// Spoken language preference.
enum RecognitionLanguage: String, CaseIterable, Identifiable {
  case japanese
  case english
  case automatic

  var id: Self { self }

  var label: String {
    switch self {
    case .japanese: "日本語"
    case .english: "英語"
    case .automatic: "端末の言語"
    }
  }

  /// Said plainly, because this is not real language detection: it uses the
  /// device's own language. Engines that can detect the spoken language are
  /// offered that choice instead.
  var detail: String {
    switch self {
    case .japanese: "日本語として文字起こしします。"
    case .english: "英語として文字起こしします。"
    case .automatic: "この端末の言語（\(Locale.current.identifier)）で文字起こしします。話された言語の自動検出ではありません。"
    }
  }

  var locale: Locale {
    switch self {
    case .japanese: Locale(identifier: "ja-JP")
    case .english: Locale(identifier: "en-US")
    case .automatic: Locale.current
    }
  }
}
