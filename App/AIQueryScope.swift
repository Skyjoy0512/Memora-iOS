import Foundation

enum AIQueryScope: Hashable {
  case file(UUID)
  case space(UUID)
  case global
}

