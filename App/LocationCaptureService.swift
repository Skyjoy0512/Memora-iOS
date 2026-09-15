import CoreLocation
import MapKit
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
      let placeName = await Self.nearestPlaceName(to: location)
      await MainActor.run {
        self.state = .found(placeName)
      }
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    state = .failed("現在地を確認できませんでした。場所名は手入力できます。")
  }

  private static func nearestPlaceName(to location: CLLocation) async -> String {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = "駅"
    request.region = MKCoordinateRegion(
      center: location.coordinate,
      latitudinalMeters: 2_000,
      longitudinalMeters: 2_000
    )

    if let response = try? await MKLocalSearch(request: request).start(),
       let nearest = response.mapItems
        .compactMap({ item -> (String, CLLocationDistance)? in
          guard let name = item.name else { return nil }
          return (name, item.placemark.location?.distance(from: location) ?? .greatestFiniteMagnitude)
        })
        .min(by: { $0.1 < $1.1 }),
       nearest.1 < 1_500 {
      return nearest.0
    }

    if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
      return placemark.name ?? placemark.locality ?? "現在地"
    }
    return "現在地"
  }
}
