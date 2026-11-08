import Foundation

@main
struct ProjectCitationLocationChecks {
  static func main() {
    precondition(ProjectCitationLocation.pageIndex(1, count: 3) == 0)
    precondition(ProjectCitationLocation.pageIndex(3, count: 3) == 2)
    for page in [-1, 0, 4, Int.max] { precondition(ProjectCitationLocation.pageIndex(page, count: 3) == nil) }
    precondition(ProjectCitationLocation.pageIndex(1, count: 0) == nil)
    // Exactly seven days is the last accepted playback position.
    precondition(ProjectCitationLocation.playbackTime(604_800) == 604_800)
    for time: Double in [Double.nan, Double.infinity, -1, -0.001, 604_801, 691_200] {
      precondition(ProjectCitationLocation.playbackTime(time) == nil)
    }
    precondition(ProjectCitationLocation.playbackTime(nil) == nil)
    precondition(ProjectCitationLocation.playbackTime(0) == 0)
    precondition(ProjectCitationLocation.playbackTime(123.5) == 123.5)
    print("ProjectCitationLocationChecks: passed (one-based pages, missing pages, finite and bounded timestamps)")
  }
}
