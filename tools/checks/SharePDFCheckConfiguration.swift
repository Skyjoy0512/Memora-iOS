import Foundation

// The app-group container is an OS boundary. All queue, model, file and SQLite
// work remains production code in this isolated host fixture.
@MainActor enum ShareInboxConfiguration {
  static var root: URL?
}
