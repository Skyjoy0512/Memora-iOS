import CoreLocation
import Foundation
import UIKit

/// Records journeys and stays into the journal from the two low-power location
/// services: significant location changes for station passes and visit
/// monitoring for stays. It is started by the app delegate, not a screen, so it
/// also runs when iOS relaunches the app in the background. Records go to a
/// local inbox the model picks up, because the model may not exist yet then.
///
/// On the main actor: the manager is created on the main thread, so its delegate
/// callbacks arrive there, and the state it keeps is only touched from one place.
@MainActor
final class AutoLocationLogger: NSObject, CLLocationManagerDelegate {
  static let shared = AutoLocationLogger()

  static let enabledKey = "memora.autoLifeLog.enabled"
  static let excludedPlacesKey = "memora.autoLifeLog.excludedPlaces"
  static let inboxKey = "memoraAutoLifeLogInbox"
  /// Set once the "always" prompt has been shown. iOS offers it only once, so a
  /// later attempt must send the person to Settings instead of waiting forever.
  private static let alwaysPromptShownKey = "memora.autoLifeLog.alwaysPromptShown"
  /// The last station recorded, so the 30-minute repeat guard survives the app
  /// being relaunched in the background for each significant change.
  private static let lastStationTitleKey = "memora.autoLifeLog.lastStationTitle"
  private static let lastStationAtKey = "memora.autoLifeLog.lastStationAt"

  /// A place events within 200 m of are not recorded.
  struct ExcludedPlace: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
  }

  /// What the debug check found, so a run that recorded nothing says why.
  enum DebugStationResult: Equatable {
    case disabled
    case denied
    case station(String)
    case noStation
    case excluded
    case failed

    var message: String {
      switch self {
      case .disabled:
        "設定がオフです。設定の「ジャーナル」で「移動と滞在を自動で記録」をオンにしてください。"
      case .denied:
        "位置情報が許可されていません。設定から「常に」を許可してください。"
      case .station(let name):
        "\(name)駅付近を通過 を記録しました。"
      case .noStation:
        "近くに駅が見つかりませんでした。"
      case .excluded:
        "この場所は「記録しない場所」に入っています。"
      case .failed:
        "現在地を確認できませんでした。"
      }
    }
  }

  private static let stationRepeatWindow: TimeInterval = 30 * 60
  private static let minimumStay: TimeInterval = 10 * 60
  private static let exclusionRadius: CLLocationDistance = 200

  /// Which permission prompt the pending enable request is waiting on.
  private enum EnablePhase {
    case askingWhenInUse
    case askingAlways
  }

  private let manager = CLLocationManager()
  private var enableCompletion: ((Bool) -> Void)?
  private var enablePhase: EnablePhase?
  /// Set while the debug screen waits for one location check's outcome.
  private var debugCompletion: ((DebugStationResult) -> Void)?

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
    switch manager.authorizationStatus {
    case .notDetermined:
      enableCompletion = completion
      enablePhase = .askingWhenInUse
      manager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse:
      // iOS shows the "always" prompt only once. If it has already been passed
      // over, do not open a prompt that will never appear: say so at once.
      guard !UserDefaults.standard.bool(forKey: Self.alwaysPromptShownKey) else {
        completion(false)
        return
      }
      enableCompletion = completion
      enablePhase = .askingAlways
      UserDefaults.standard.set(true, forKey: Self.alwaysPromptShownKey)
      manager.requestAlwaysAuthorization()
    case .denied, .restricted:
      completion(false)
    @unknown default:
      completion(false)
    }
  }

  /// Called when the app returns to the front. If a permission request is still
  /// unanswered (the person chose "keep when in use" without a callback), it is
  /// finished as a refusal so the setting does not hang.
  func resolvePendingEnableOnActivation() {
    guard enableCompletion != nil else { return }
    guard manager.authorizationStatus == .authorizedAlways else {
      finishEnable(granted: false)
      return
    }
    finishEnable(granted: true)
  }

  private func finishEnable(granted: Bool) {
    let completion = enableCompletion
    enableCompletion = nil
    enablePhase = nil
    if granted {
      UserDefaults.standard.set(true, forKey: Self.enabledKey)
      startMonitoring()
    }
    completion?(granted)
  }

  func disable() {
    UserDefaults.standard.set(false, forKey: Self.enabledKey)
    stopMonitoring()
  }

  /// Runs one station check from the current location, for the debug screen, and
  /// reports what it found so a run without a station is distinguishable.
  func debugEvaluateCurrentLocation(completion: @escaping (DebugStationResult) -> Void) {
    guard Self.isEnabled else {
      completion(.disabled)
      return
    }
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      debugCompletion = completion
      manager.requestLocation()
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
      completion(.denied)
    case .denied, .restricted:
      completion(.denied)
    @unknown default:
      completion(.failed)
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
      switch enablePhase {
      case .askingWhenInUse:
        // "When in use" was just granted; now ask for "always", which the
        // background monitors need.
        enablePhase = .askingAlways
        UserDefaults.standard.set(true, forKey: Self.alwaysPromptShownKey)
        manager.requestAlwaysAuthorization()
      case .askingAlways:
        // The "always" prompt was answered with "keep when in use"; it will not
        // be offered again, so finish as a refusal and let the UI explain.
        finishEnable(granted: false)
      case nil:
        break
      }
    case .authorizedAlways:
      if enableCompletion != nil {
        finishEnable(granted: true)
      }
    case .denied, .restricted:
      if enableCompletion != nil {
        finishEnable(granted: false)
      }
    case .notDetermined:
      break
    @unknown default:
      break
    }
  }

  // MARK: - Locations

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else {
      completeDebug(with: .failed)
      return
    }
    // Significant changes are coarse; a fix poorer than a kilometre is not a
    // reliable station.
    guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 1_000 else {
      completeDebug(with: .failed)
      return
    }
    if debugCompletion != nil {
      runProtected {
        self.completeDebug(with: await self.recordStationPass(at: location))
      }
      return
    }
    guard Self.isEnabled else { return }
    runProtected { await self.recordStationPass(at: location) }
  }

  private func completeDebug(with result: DebugStationResult) {
    let completion = debugCompletion
    debugCompletion = nil
    completion?(result)
  }

  /// Keeps the work alive to its end when the app was launched in the background
  /// for a location event: without this, the system can suspend it before the
  /// inbox write lands.
  private func runProtected(_ operation: @escaping @MainActor () async -> Void) {
    Task { @MainActor in
      let taskID = UIApplication.shared.beginBackgroundTask(withName: "AutoLifeLog")
      await operation()
      if taskID != .invalid {
        UIApplication.shared.endBackgroundTask(taskID)
      }
    }
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
    runProtected { await self.recordVisit(at: location, arrival: arrival, departure: departure) }
  }

  @discardableResult
  private func recordStationPass(at location: CLLocation) async -> DebugStationResult {
    guard !Self.isExcluded(location) else { return .excluded }
    guard let station = await PlaceNameResolver.nearestStation(to: location),
          station.location.distance(from: location) <= 400 else { return .noStation }

    let base = PlaceNameResolver.stationNameWithoutSuffix(station.name)
    let title = "\(base)駅付近を通過"
    let now = Date.now

    // The guard is kept in UserDefaults: a significant change can relaunch the
    // app as a fresh process, where an in-memory value would be gone.
    let defaults = UserDefaults.standard
    if defaults.string(forKey: Self.lastStationTitleKey) == title,
       let stamp = defaults.object(forKey: Self.lastStationAtKey) as? Double,
       now.timeIntervalSince1970 - stamp < Self.stationRepeatWindow {
      return .station(base)
    }
    if await inboxHasRecent(title: title, within: Self.stationRepeatWindow, now: now) {
      return .station(base)
    }
    defaults.set(title, forKey: Self.lastStationTitleKey)
    defaults.set(now.timeIntervalSince1970, forKey: Self.lastStationAtKey)

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
    return .station(base)
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
      // The model may be alive in the foreground; let it take the record now
      // instead of waiting for the next activation.
      NotificationCenter.default.post(name: .autoLifeLogInboxDidChange, object: nil)
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

extension Notification.Name {
  /// Posted when the automatic logger adds a record to its inbox, so a running
  /// model can import it without waiting for the app to be reactivated.
  static let autoLifeLogInboxDidChange = Notification.Name("memoraAutoLifeLogInboxDidChange")
}
