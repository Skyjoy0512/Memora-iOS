import CoreLocation
import Foundation

/// Records journeys and stays into the journal from the two low-power location
/// services: significant location changes for station passes and visit
/// monitoring for stays. It is started by the app delegate, not a screen, so it
/// also runs when iOS relaunches the app in the background. Records go to a
/// local inbox the model picks up, because the model may not exist yet then.
final class AutoLocationLogger: NSObject, CLLocationManagerDelegate {
  static let shared = AutoLocationLogger()

  static let enabledKey = "memora.autoLifeLog.enabled"
  static let excludedPlacesKey = "memora.autoLifeLog.excludedPlaces"
  static let inboxKey = "memoraAutoLifeLogInbox"

  /// A place events within 200 m of are not recorded.
  struct ExcludedPlace: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
  }

  private static let stationRepeatWindow: TimeInterval = 30 * 60
  private static let minimumStay: TimeInterval = 10 * 60
  private static let exclusionRadius: CLLocationDistance = 200

  private let manager = CLLocationManager()
  private var enableCompletion: ((Bool) -> Void)?
  private var lastStationTitle: String?
  private var lastStationAt: Date?

  static var isEnabled: Bool {
    UserDefaults.standard.bool(forKey: enabledKey)
  }

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  /// Starts the monitors if the setting is on and permission allows. Called at
  /// launch; a background relaunch also lands here.
  func startIfEnabled() {
    guard Self.isEnabled, manager.authorizationStatus == .authorizedAlways else { return }
    startMonitoring()
  }

  /// Turns the feature on, asking for "when in use" and then "always". The
  /// completion runs on the main thread with whether "always" was granted.
  func enable(completion: @escaping (Bool) -> Void) {
    if manager.authorizationStatus == .authorizedAlways {
      UserDefaults.standard.set(true, forKey: Self.enabledKey)
      startMonitoring()
      completion(true)
      return
    }
    enableCompletion = completion
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse:
      manager.requestAlwaysAuthorization()
    case .denied, .restricted:
      enableCompletion = nil
      completion(false)
    @unknown default:
      enableCompletion = nil
      completion(false)
    }
  }

  func disable() {
    UserDefaults.standard.set(false, forKey: Self.enabledKey)
    stopMonitoring()
  }

  /// Runs one station check from the current location, for the debug screen.
  func debugEvaluateCurrentLocation() {
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .denied, .restricted:
      break
    @unknown default:
      break
    }
  }

  private func startMonitoring() {
    manager.startMonitoringSignificantLocationChanges()
    manager.startMonitoringVisits()
  }

  private func stopMonitoring() {
    manager.stopMonitoringSignificantLocationChanges()
    manager.stopMonitoringVisits()
  }

  // MARK: - Authorization

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    switch manager.authorizationStatus {
    case .authorizedWhenInUse:
      // "Always" is what background monitoring needs, so ask for it next.
      if enableCompletion != nil {
        manager.requestAlwaysAuthorization()
      }
    case .authorizedAlways:
      if let completion = enableCompletion {
        enableCompletion = nil
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        startMonitoring()
        completion(true)
      }
    case .denied, .restricted:
      if let completion = enableCompletion {
        enableCompletion = nil
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        completion(false)
      }
    case .notDetermined:
      break
    @unknown default:
      break
    }
  }

  // MARK: - Locations

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard Self.isEnabled, let location = locations.last else { return }
    // Significant changes are coarse; a fix poorer than a kilometre is not a
    // reliable station.
    guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 1_000 else { return }
    Task { await recordStationPass(at: location) }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    // A failed fix is not worth surfacing; the next one may succeed.
  }

  func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    guard Self.isEnabled else { return }
    let arrival = visit.arrivalDate
    let departure = visit.departureDate
    // Both ends must be known, or the stay is still in progress.
    guard arrival != .distantPast, departure != .distantFuture, departure > arrival else { return }
    guard departure.timeIntervalSince(arrival) >= Self.minimumStay else { return }

    let location = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
    guard !Self.isExcluded(location) else { return }
    Task { await recordVisit(at: location, arrival: arrival, departure: departure) }
  }

  private func recordStationPass(at location: CLLocation) async {
    guard !Self.isExcluded(location) else { return }
    guard let station = await PlaceNameResolver.nearestStation(to: location),
          station.location.distance(from: location) <= 400 else { return }

    let base = PlaceNameResolver.stationNameWithoutSuffix(station.name)
    let title = "\(base)駅付近を通過"
    let now = Date.now

    if lastStationTitle == title, let last = lastStationAt,
       now.timeIntervalSince(last) < Self.stationRepeatWindow {
      return
    }
    if await inboxHasRecent(title: title, within: Self.stationRepeatWindow, now: now) {
      return
    }
    lastStationTitle = title
    lastStationAt = now

    appendToInbox(
      LifeLogEntry(
        id: UUID(),
        createdAt: now,
        title: title,
        summary: "移動中に自動で記録しました。",
        source: .automatic,
        meetingID: nil,
        kind: .location,
        origin: .stationPass,
        latitude: Self.rounded(location.coordinate.latitude),
        longitude: Self.rounded(location.coordinate.longitude)
      )
    )
  }

  private func recordVisit(at location: CLLocation, arrival: Date, departure: Date) async {
    let name = await PlaceNameResolver.nearestPlaceName(to: location)
    let title = "\(name)に滞在"
    if await inboxHasRecent(title: title, within: Self.minimumStay, now: arrival) {
      return
    }
    appendToInbox(
      LifeLogEntry(
        id: UUID(),
        createdAt: arrival,
        title: title,
        summary: "滞在を自動で記録しました。",
        source: .automatic,
        meetingID: nil,
        kind: .location,
        origin: .visit,
        endDate: departure,
        latitude: Self.rounded(location.coordinate.latitude),
        longitude: Self.rounded(location.coordinate.longitude)
      )
    )
  }

  // MARK: - Inbox

  /// Adds a record to the inbox the model imports. Kept local and small: no
  /// address or raw path, only the name and a rounded coordinate.
  private func appendToInbox(_ entry: LifeLogEntry) {
    Task { @MainActor in
      var entries: [LifeLogEntry] = []
      if case .data(let data) = RecordStore.load(Self.inboxKey),
         let decoded = try? JSONDecoder().decode([LifeLogEntry].self, from: data) {
        entries = decoded
      }
      entries.append(entry)
      try? RecordStore.saveNow(entries, key: Self.inboxKey)
    }
  }

  @MainActor
  private func inboxHasRecent(title: String, within: TimeInterval, now: Date) -> Bool {
    guard case .data(let data) = RecordStore.load(Self.inboxKey),
          let entries = try? JSONDecoder().decode([LifeLogEntry].self, from: data) else {
      return false
    }
    return entries.contains {
      $0.title == title && now.timeIntervalSince($0.createdAt) < within && now.timeIntervalSince($0.createdAt) >= 0
    }
  }

  // MARK: - Excluded places

  static var excludedPlaces: [ExcludedPlace] {
    guard let data = UserDefaults.standard.data(forKey: excludedPlacesKey),
          let list = try? JSONDecoder().decode([ExcludedPlace].self, from: data) else {
      return []
    }
    return list
  }

  static func addExcludedPlace(name: String, latitude: Double, longitude: Double) {
    var list = excludedPlaces
    list.append(ExcludedPlace(id: UUID(), name: name, latitude: latitude, longitude: longitude))
    if let data = try? JSONEncoder().encode(list) {
      UserDefaults.standard.set(data, forKey: excludedPlacesKey)
    }
  }

  static func removeExcludedPlace(_ id: UUID) {
    let list = excludedPlaces.filter { $0.id != id }
    if let data = try? JSONEncoder().encode(list) {
      UserDefaults.standard.set(data, forKey: excludedPlacesKey)
    }
  }

  static func isExcluded(_ location: CLLocation) -> Bool {
    excludedPlaces.contains { place in
      CLLocation(latitude: place.latitude, longitude: place.longitude)
        .distance(from: location) <= exclusionRadius
    }
  }

  /// Three decimals is about 100 m, enough to name a place without pinning an
  /// address.
  static func rounded(_ value: Double) -> Double {
    (value * 1_000).rounded() / 1_000
  }
}
