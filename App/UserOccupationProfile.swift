import Foundation

struct UserOccupationProfile: Codable, Equatable {
  var selectedOccupationIDs: [String] = []
  var primaryOccupationID: String?
  var customOccupationName = ""
  var updatedAt: Date = .now

  mutating func select(_ id: String, isSelected: Bool) {
    selectedOccupationIDs.removeAll { $0 == id }
    if isSelected { selectedOccupationIDs.append(id) }
    if primaryOccupationID == id && !isSelected { primaryOccupationID = nil }
    if primaryOccupationID == nil { primaryOccupationID = selectedOccupationIDs.first }
    updatedAt = .now
  }

  var orderedIDs: [String] {
    var seen: Set<String> = []
    let primary = primaryOccupationID.flatMap { selectedOccupationIDs.contains($0) ? $0 : nil }
    return ([primary].compactMap { $0 } + selectedOccupationIDs).filter { seen.insert($0).inserted }
  }
}
