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

  private(set) var state = State.idle
  @ObservationIgnored private let manager = CLLocationManager()

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
      return
    }

    Task {
      let placeName = await PlaceNameResolver.nearestPlaceName(to: location)
      await MainActor.run {
        self.state = .found(placeName)
      }
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    state = .failed("現在地を確認できませんでした。場所名は手入力できます。")
  }
}
