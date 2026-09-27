import SwiftUI

enum ThinkingOrbState {
  case breathing
  case searching
  case listening

  var speed: Double {
    switch self {
    case .breathing: 0.55
    case .searching: 1
    case .listening: 1.25
    }
  }
}
