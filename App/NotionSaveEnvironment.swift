import Foundation

struct NotionSaveEnvironment {
  private static let session = CloudHTTPTransport.hardenedSession()

  var configuration: () -> NotionSaveConfiguration?
  var transport: (URLRequest) async throws -> (Data, URLResponse)

  static var live: Self {
    Self(configuration: NotionService.currentConfiguration,
      transport: { request in
        let (data, response) = try await session.data(for: request)
        try CloudHTTPTransport.rejectRefusedRedirect(response)
        return (data, response)
      })
  }
}
