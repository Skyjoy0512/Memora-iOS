import Foundation

/// The engine offered by the Ask AI composer.
enum AIModel: String, CaseIterable, Identifiable {
  case standard
  case mini
  case onDevice

  var id: Self { self }

  var title: String {
    switch self {
    case .standard: "GPT-5.2"
    case .mini: "GPT-5.2 mini"
    case .onDevice: "端末内"
    }
  }

  var symbol: String {
    switch self {
    case .standard: "sparkles"
    case .mini: "bolt"
    case .onDevice: "iphone"
    }
  }
}
