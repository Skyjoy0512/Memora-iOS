import CoreLocation
import Observation

@Observable
final class LocationCaptureService: NSObject, CLLocationManagerDelegate {
  enum State: Equatable {
    case idle
    case locating
    case found(String)
    case failed(String)
  }

  /// A place with its coordinate, for callers that need to store where it is.
  enum LocatedPlace {
    case found(name: String, latitude: Double, longitude: Double)
    case failed(String)
  }

  private(set) var state = State.idle
  @ObservationIgnored private let manager = CLLocationManager()
  private var placeCompletion: ((LocatedPlace) -> Void)?

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  func requestCurrentPlace() {
    state = .locating
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      state = .failed("位置情報を許可するか、場所名を入力してください。")
    @unknown default:
      state = .failed("現在地を確認できませんでした。")
    }
  }

  /// Resolves the current place and its coordinate, for a caller that needs to
  /// remember the spot (such as adding an excluded place).
  func requestCurrentPlace(completion: @escaping (LocatedPlace) -> Void) {
    placeCompletion = completion
    state = .locating
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      placeCompletion = nil
      completion(.failed("位置情報を許可するか、場所名を入力してください。"))
    @unknown default:
      placeCompletion = nil
      completion(.failed("現在地を確認できませんでした。"))
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard state == .locating else { return }
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      state = .failed("位置情報を許可するか、場所名を入力してください。")
    case .notDetermined:
      break
    @unknown default:
      state = .failed("現在地を確認できませんでした。")
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else {
      state = .failed("現在地を確認できませんでした。")
      placeCompletion?(.failed("現在地を確認できませんでした。"))
      placeCompletion = nil
      return
    }

    Task {
      let placeName = await PlaceNameResolver.nearestPlaceName(to: location)
      await MainActor.run {
        self.state = .found(placeName)
        if let completion = self.placeCompletion {
          self.placeCompletion = nil
          completion(
            .found(
              name: placeName,
              latitude: AutoLocationLogger.rounded(location.coordinate.latitude),
              longitude: AutoLocationLogger.rounded(location.coordinate.longitude)
            )
          )
        }
      }
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    state = .failed("現在地を確認できませんでした。場所名は手入力できます。")
    placeCompletion?(.failed("現在地を確認できませんでした。"))
    placeCompletion = nil
  }
}
