import Foundation

@main
enum CatalogPresentationChecks {
  static func main() {
    let services = IntegrationCatalog.services
    precondition(Set(services.map(\.id)).count == services.count)
    precondition(services.first { $0.id == "notion" }?.toolNames == ["save_to_notion"])
    for id in ["drive"] {
      let service = services.first { $0.id == id }!
      precondition(!service.isImplemented && service.toolNames.isEmpty)
    }
    for id in ["github", "linear"] {
      let service = services.first { $0.id == id }!
      precondition(service.isImplemented && service.capabilities.count == 2 && service.toolNames.isEmpty)
    }
    precondition(LibrarySection.projects.searchPrompt.contains("名"))
    print("CatalogPresentationChecks: passed (Notion write-only, unavailable Drive, GitHub/Linear MCP read-only, named project search)")
  }
}
