import CoreLocation
import Foundation
import SQLite3
import Synchronization

@main @MainActor
struct LocationPersistenceChecks {
  static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1])
    let suite = "MemoraLocationChecks-\(UUID())"
    AutoLocationLogger.defaults = UserDefaults(suiteName: suite)!
    defer { AutoLocationLogger.defaults.removePersistentDomain(forName: suite) }
    let events = Mutex((changes: 0, failures: 0))
    let changes = NotificationCenter.default.addObserver(forName: .autoLifeLogInboxDidChange, object: nil, queue: nil) { _ in
      events.withLock { $0.changes += 1 }
    }
    let failures = NotificationCenter.default.addObserver(forName: LocalSaveFailure.notification, object: nil, queue: nil) { _ in
      events.withLock { $0.failures += 1 }
    }
    defer { NotificationCenter.default.removeObserver(changes); NotificationCenter.default.removeObserver(failures) }
    let location = CLLocation(latitude: 35.123456, longitude: 139.123456)
    PlaceNameResolver.stationLocation = location
    let logger = AutoLocationLogger()
    let url = root.appendingPathComponent("location.sqlite")
    RecordStore.store = LocalStore(fileURL: url)
    try RecordStore.store.prepare()
    expect(await logger.station(location) == .station("検証"))
    let first = try entries()
    precondition(first.count == 1 && first[0].latitude == 35.123 && first[0].longitude == 139.123)
    expect(await logger.station(location) == .station("検証"))
    precondition(events.withLock { $0.changes == 1 && $0.failures == 0 })
    expect(try entries().count == 1)

    // A decode or read failure cannot turn the existing bytes into an empty inbox.
    for readFails in [false, true] {
      resetSettings()
      let original = readFails ? try JSONEncoder().encode(first) : Data("broken inbox".utf8)
      try RecordStore.store.write(AutoLocationLogger.inboxKey, data: original)
      RecordStore.failsReading = readFails
      expect(await logger.station(location) == .saveFailed)
      RecordStore.failsReading = false
      precondition(readBytes() == original)
      precondition(AutoLocationLogger.defaults.object(forKey: AutoLocationLogger.lastStationAtKey) == nil)
    }
    precondition(events.withLock { $0.changes == 1 && $0.failures == 2 })
    try RecordStore.store.write(AutoLocationLogger.inboxKey, data: JSONEncoder().encode([LifeLogEntry]()))
    var db: OpaquePointer?
    precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    precondition(sqlite3_exec(db, "CREATE TRIGGER reject_location BEFORE INSERT ON documents BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil) == SQLITE_OK)
    expect(await logger.station(location) == .saveFailed)
    expect(try entries().isEmpty)
    precondition(AutoLocationLogger.defaults.object(forKey: AutoLocationLogger.lastStationAtKey) == nil)
    precondition(events.withLock { $0.changes == 1 && $0.failures == 3 })
    precondition(sqlite3_exec(db, "DROP TRIGGER reject_location", nil, nil, nil) == SQLITE_OK)
    expect(await logger.station(location) == .station("検証"))
    expect(try entries().count == 1)

    // Both await points must revalidate settings, permission, exclusion and cancellation.
    for visit in [false, true] {
      for change in 0..<5 {
        resetSettings()
        logger.manager.authorizationStatus = .authorizedAlways
        AutoLocationLogger.excluded = false
        try RecordStore.store.write(AutoLocationLogger.inboxKey, data: JSONEncoder().encode([LifeLogEntry]()))
        let gate = LocationLookupGate()
        PlaceNameResolver.lookup = { await gate.wait() }
        let operation = Task {
          if visit { await logger.visit(location); return AutoLocationLogger.DebugStationResult.station("visit") }
          return await logger.station(location)
        }
        await gate.entered()
        switch change {
        case 0: AutoLocationLogger.enabled = false
        case 1: logger.manager.authorizationStatus = .denied
        case 2: AutoLocationLogger.excluded = true
        case 3: logger.locationGeneration = UUID()
        default: operation.cancel()
        }
        gate.resume()
        let result = await operation.value
        if !visit { precondition(result != .station("検証")) }
        expect(try entries().isEmpty)
      }
    }
    PlaceNameResolver.lookup = nil
    resetSettings()
    AutoLocationLogger.excluded = false
    logger.manager.authorizationStatus = .authorizedWhenInUse
    expect(await logger.station(location) == .denied)
    expect(await logger.station(location, debug: true) == .station("検証"))
    resetSettings()
    logger.manager.authorizationStatus = .authorizedAlways
    try RecordStore.store.write(AutoLocationLogger.inboxKey, data: JSONEncoder().encode([LifeLogEntry]()))
    await logger.visit(location)
    expect(try entries().count == 1)
    print("PASS: production station/visit/inbox methods with real SQLite; unreadable inbox preserved, failed commit has no success notification or repeat marker, retry succeeds, stale settings/permissions/exclusions/generations and cancelled lookups refused. Location, place lookup and settings are isolated fixtures; no device or network.")
  }

  static func expect(_ value: Bool) { precondition(value) }

  static func resetSettings() {
    AutoLocationLogger.enabled = true
    AutoLocationLogger.defaults.removeObject(forKey: AutoLocationLogger.lastStationAtKey)
    AutoLocationLogger.defaults.removeObject(forKey: AutoLocationLogger.lastStationTitleKey)
  }
  static func readBytes() -> Data {
    guard case .data(let data) = RecordStore.store.readOutcome(AutoLocationLogger.inboxKey) else { preconditionFailure() }
    return data
  }
  static func entries() throws -> [LifeLogEntry] { try JSONDecoder().decode([LifeLogEntry].self, from: readBytes()) }
}

@MainActor final class AutoLocationLogger {
  static let inboxKey = "inbox"
  static let lastStationTitleKey = "station.title"
  static let lastStationAtKey = "station.at"
  static let stationRepeatWindow: TimeInterval = 1800
  static let minimumStay: TimeInterval = 600
  static var defaults = UserDefaults(suiteName: "MemoraLocationChecks-Unused-\(UUID())")!
  static var enabled = true
  static var excluded = false
  static var isEnabled: Bool { enabled }
  var locationGeneration = UUID()
  var manager = LocationManagerFixture()
  static func isExcluded(_ location: CLLocation) -> Bool { excluded }
  static func rounded(_ value: Double) -> Double { (value * 1000).rounded() / 1000 }
}
enum LocationAuthorizationFixture { case authorizedAlways, authorizedWhenInUse, denied }
@MainActor final class LocationManagerFixture { var authorizationStatus: LocationAuthorizationFixture = .authorizedAlways }
@MainActor enum PlaceNameResolver {
  struct Station { var name: String; var location: CLLocation }
  static var stationLocation = CLLocation(latitude: 0, longitude: 0)
  static var lookup: (() async -> Void)?
  static func nearestStation(to location: CLLocation) async -> Station? {
    await lookup?()
    return .init(name: "検証駅", location: stationLocation)
  }
  static func stationNameWithoutSuffix(_ name: String) -> String { String(name.dropLast()) }
  static func nearestPlaceName(to location: CLLocation) async -> String { await lookup?(); return "検証場所" }
}
@MainActor final class LocationLookupGate {
  var continuation: CheckedContinuation<Void, Never>?
  func wait() async { await withCheckedContinuation { continuation = $0 } }
  func entered() async { while continuation == nil { await Task.yield() } }
  func resume() { let waiting = continuation; continuation = nil; waiting?.resume() }
}
@MainActor enum RecordStore {
  enum LoadOutcome { case absent, failed; case data(Data) }
  static var store: LocalStore!
  static var failsReading = false
  static func load(_ key: String) -> LoadOutcome {
    guard !failsReading else { return .failed }
    switch store.readOutcome(key) {
    case .missing: return .absent
    case .failed: return .failed
    case .data(let data): return .data(data)
    }
  }
  static func saveNow<T: Encodable>(_ value: T, key: String) throws { try store.write(key, data: JSONEncoder().encode(value)) }
}
enum MediaFiles { static func writePhoto(_ data: Data) -> String? { preconditionFailure("No photos in location records") } }
extension Notification.Name { static let autoLifeLogInboxDidChange = Notification.Name("memoraAutoLifeLogInboxDidChange") }
