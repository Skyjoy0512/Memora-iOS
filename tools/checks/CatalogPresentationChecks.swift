import Foundation

@main
enum CatalogPresentationChecks {
  static func main() {
    let services = IntegrationCatalog.services
    precondition(Set(services.map(\.id)).count == services.count)
    precondition(services.first { $0.id == "notion" }?.toolNames == ["save_to_notion"])
    for id in ["drive", "github"] {
      let service = services.first { $0.id == id }!
      precondition(!service.isImplemented && service.toolNames.isEmpty)
    }
    precondition(LibrarySection.projects.searchPrompt.contains("名"))
    print("CatalogPresentationChecks: passed (honest Notion capabilities, unavailable Drive/GitHub, named project search)")
  }
}
