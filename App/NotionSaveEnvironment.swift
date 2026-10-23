import Foundation

struct NotionSaveEnvironment {
  var configuration: () -> NotionSaveConfiguration?
  var transport: (URLRequest) async throws -> (Data, URLResponse)

  static var live: Self {
    Self(configuration: NotionService.currentConfiguration,
      transport: { try await URLSession.shared.data(for: $0) })
  }
}
