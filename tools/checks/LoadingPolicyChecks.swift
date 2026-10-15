import Foundation

@main
enum LoadingPolicyChecks {
  static func main() {
    for (milliseconds, stage) in [(0, 0), (50, 0), (150, 0), (180, 1), (200, 1), (1999, 1), (2000, 2), (4999, 2), (5000, 3)] {
      precondition(MemoraLoadingPolicy.stage(after: .milliseconds(milliseconds)) == stage)
    }
    var load = MemoraLoadSnapshot<String, [String]>()
    precondition(load.state == .idle)
    let old = load.begin("A")
    let latest = load.begin("B")
    load.finish(["old"], isEmpty: false, token: old)
    precondition(load.value(for: "A") == nil && load.value(for: "B") == nil && load.state == .loading)
    load.finish(["current"], isEmpty: false, token: latest)
    let refresh = load.begin("B")
    precondition(load.state == .refreshing && load.value(for: "B") == ["current"])
    load.fail("mock failure", token: refresh)
    precondition(load.state == .failed && load.value == ["current"])
    let retry = load.begin("B")
    load.cancel(retry)
    load.finish(["cancelled"], isEmpty: false, token: retry)
    precondition(load.value == ["current"] && load.state == .loaded)
    let empty = load.begin("C")
    precondition(load.value == nil)
    load.finish([], isEmpty: true, token: empty)
    precondition(load.state == .empty && !load.state.isWorking)
    let failure = load.begin("D")
    load.fail("unreadable", token: failure)
    precondition(load.state == .failed && load.failure == "unreadable")
    let request = JournalCalendarRequest(date: Date(timeIntervalSince1970: 123), calendarIDs: ["mock"], enabled: true, refresh: 0)
    var refreshed = request
    refreshed.refresh = 1
    precondition(request != refreshed && request.contentKey == refreshed.contentKey)
    var day = refreshed
    day.date.addTimeInterval(86400)
    precondition(day.contentKey != request.contentKey)
    print("LoadingPolicyChecks: passed (50/200/2000/5000ms virtual clock, stale/overlap/cancel/retry, refresh keeps content, empty/failure, calendar day/settings identity)")
  }
}
