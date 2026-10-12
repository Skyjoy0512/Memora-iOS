import Foundation

enum ProjectWorkspaceItem: Identifiable {
  case source(ProjectSource)
  case recording(Meeting)
  case document(MemoraDocument)

  var id: String {
    switch self {
    case .source(let value): "source-\(value.id)"
    case .recording(let value): "recording-\(value.id)"
    case .document(let value): "document-\(value.id)"
    }
  }

  var date: Date {
    switch self {
    case .source(let value): value.createdAt
    case .recording(let value): value.createdAt
    case .document(let value): value.updatedAt
    }
  }

  var title: String {
    switch self {
    case .source(let value): value.title
    case .recording(let value): value.displayTitle
    case .document(let value): value.displayTitle
    }
  }

  var route: LibraryRoute {
    switch self {
    case .source(let value): .projectSource(value.id)
    case .recording(let value): .meeting(value.id)
    case .document(let value): .document(value.id)
    }
  }
}
