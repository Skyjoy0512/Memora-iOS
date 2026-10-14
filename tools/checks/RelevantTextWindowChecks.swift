import Foundation

@main
struct RelevantTextWindowChecks {
  static func main() {
    let source = String(repeating: "前😀", count: 1_000) + "末尾決定Token" + String(repeating: "後", count: 1_000)
    for limit in [0, 1, 2, 15, 30, 100, 500, 10_000] {
      let result = RelevantTextWindow.text(source, matching: ["決定", "末尾決定Token"], maximumCharacters: limit)
      precondition(result.count <= limit)
      if limit >= 15 { precondition(result.contains("末尾決定Token")) }
    }
    let reverse = RelevantTextWindow.text(source, matching: ["末尾決定Token", "決定"], maximumCharacters: 50)
    let forward = RelevantTextWindow.text(source, matching: ["決定", "末尾決定Token"], maximumCharacters: 50)
    precondition(reverse == forward && forward.hasPrefix("…"))
    precondition(RelevantTextWindow.text("短い本文", matching: [], maximumCharacters: 100) == "短い本文")
    precondition(RelevantTextWindow.text("ABCDEF", matching: ["def"], maximumCharacters: 5).contains("DEF"))
    precondition(RelevantTextWindow.text(source, matching: [], maximumCharacters: 100).count == 100)
    precondition(RelevantTextWindow.text(source, matching: ["不一致"], maximumCharacters: -1).isEmpty)
    print("RelevantTextWindowChecks: passed (long Japanese/emoji passages, specific term selection, case-insensitive match, deterministic order, bounded/empty fallback)")
  }
}
