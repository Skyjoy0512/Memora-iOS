import Foundation

@main
struct SystemIntegrationChecks {
  static func main() throws {
    let id = UUID()
    for link in [MemoraAppLink.askAI, .journal, .tasks, .todayTasks, .newMemo, .projects, .project(id)] {
      precondition(MemoraAppLink(url: link.url) == link)
    }
    for value in ["https://ask-ai", "memora://ask-ai/extra", "memora://ask-ai?command=record",
                  "memora://user@ask-ai", "memora://ask-ai:443", "memora://tasks#private",
                  "memora://project/not-a-uuid", "memora://project/\(id)/extra", "memora://unknown"] {
      precondition(MemoraAppLink(url: URL(string: value)!) == nil)
    }
    precondition(MemoraAppLink(url: URL(string: "MEMORA://ASK-AI")!) == .askAI)
    let now = Date.now
    var snapshot = MemoraWidgetSnapshot(generatedAt: now, day: Calendar.current.startOfDay(for: now),
      openTaskCount: 2, recordCount: 3, projects: [.init(id: id, name: "Fixture", openTaskCount: 1)])
    precondition(snapshot.isValid(at: now))
    precondition(!snapshot.isValid(at: now.addingTimeInterval(8 * 3_600 + 1)))
    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(MemoraWidgetSnapshot.self, from: data)
    precondition(decoded == snapshot)
    snapshot.projects.append(snapshot.projects[0])
    precondition(!snapshot.isValid(at: now))
    snapshot.projects.removeLast()
    snapshot.projects[0].name = " "
    precondition(!snapshot.isValid(at: now))
    snapshot.projects[0].name = "Fixture"
    snapshot.projects[0].lastRecordAt = now.addingTimeInterval(120)
    precondition(!snapshot.isValid(at: now))
    snapshot.projects[0].lastRecordAt = nil
    snapshot.openTaskCount = -1
    precondition(!snapshot.isValid(at: now))
    snapshot.openTaskCount = 2
    snapshot.generatedAt = now.addingTimeInterval(120)
    precondition(!snapshot.isValid(at: now))
    snapshot.generatedAt = now
    snapshot.day = now.addingTimeInterval(-24 * 3_600)
    precondition(!snapshot.isValid(at: now))
    snapshot.day = Calendar.current.startOfDay(for: now)
    snapshot.nextEventAt = now.addingTimeInterval(-60)
    precondition(!snapshot.isValid(at: now))
    snapshot.nextEventAt = nil
    let directory = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("snapshot-fixture-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("snapshot.json")
    precondition(MemoraWidgetSnapshotStore.read(from: url) == nil)
    try MemoraWidgetSnapshotStore.write(snapshot, to: url)
    precondition(MemoraWidgetSnapshotStore.read(from: url, now: now) == snapshot)
    precondition(MemoraWidgetSnapshotStore.read(from: url, now: now.addingTimeInterval(9 * 3_600)) == nil)
    try Data("invalid".utf8).write(to: url)
    precondition(MemoraWidgetSnapshotStore.read(from: url) == nil)
    try Data(repeating: 32, count: 64 * 1024 + 1).write(to: url)
    precondition(MemoraWidgetSnapshotStore.read(from: url) == nil)
    snapshot.recordCount = -1
    do { try MemoraWidgetSnapshotStore.write(snapshot, to: url); preconditionFailure("Accepted invalid snapshot") }
    catch MemoraWidgetSnapshotStore.StoreFailure.unavailable {}
    print("SystemIntegrationChecks: passed (local destinations, malformed links, snapshot roundtrip, expiry, identity/date/count bounds, missing/corrupt/oversize files)")
  }
}
