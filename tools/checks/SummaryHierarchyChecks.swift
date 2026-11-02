import Foundation

@main struct SummaryHierarchyChecks {
  @MainActor static func main() async {
    var calls = 0
    let source = ["a", "b", "c", "d"].map { String(repeating: $0, count: 400) }
    let result = await SummaryNoteHierarchy.reduce(source, limit: 1000) { group in
      calls += 1
      precondition(group.joined(separator: "\n\n").count <= 1000)
      return .success(group.map { String($0.first!) }.joined())
    }
    guard case .success(let reduced) = result else { preconditionFailure("Hierarchy failed") }
    precondition(reduced.joined() == "abcd" && calls == 2)
    let small = await SummaryNoteHierarchy.reduce(["untouched"], limit: 1000) { _ in
      preconditionFailure("Short request made an extra call")
    }
    guard case .success(let original) = small else { preconditionFailure("Small notes failed") }
    precondition(original == ["untouched"])
    let expanding = await SummaryNoteHierarchy.reduce(source, limit: 1000) { group in
      .success(group.joined(separator: "\n\n"))
    }
    guard case .failure(.executionLimit) = expanding else { preconditionFailure("Expansion loop accepted") }
    let oversized = await SummaryNoteHierarchy.reduce([String(repeating: "x", count: 1001)], limit: 1000) { _ in
      preconditionFailure("Oversized note was sent")
    }
    guard case .failure(.executionLimit) = oversized else { preconditionFailure("Oversized note accepted") }
    let stopped = await Task { @MainActor in
      withUnsafeCurrentTask { $0?.cancel() }
      return await SummaryNoteHierarchy.reduce(source, limit: 1000) { _ in
        preconditionFailure("Cancelled hierarchy sent a request")
      }
    }.value
    guard case .failure(.cancelled) = stopped else { preconditionFailure("Cancellation ignored") }
    print("SummaryHierarchyChecks: PASS. All ordered inputs retained by fixture reducer; bounded merge groups; no extra short-input call; oversized/expanding output and cancellation stop. No live LLM quality claim.")
  }
}
