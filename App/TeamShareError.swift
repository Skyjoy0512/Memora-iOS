import Foundation

/// Why a team share could not be produced.
enum TeamShareError: LocalizedError {
  case requiresTeamPlan
  case empty
  case privacyRestricted

  var errorDescription: String? {
    switch self {
    case .requiresTeamPlan:
      "チーム共有はチームプランで利用できます。"
    case .empty:
      "共有するファイルが選ばれていません。"
    case .privacyRestricted:
      RecordAccessPolicy.refusal
    }
  }
}
