import Foundation

enum AIInterfaceReferenceTarget: Hashable {
  case document(UUID)
  case meeting(UUID)
  case project(UUID)
}
