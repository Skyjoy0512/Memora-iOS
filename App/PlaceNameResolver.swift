import CoreLocation
import MapKit

/// Turns a coordinate into a readable place name. Shared so the manual place
/// picker and the automatic logger name a place the same way.
enum PlaceNameResolver {
  static func nearestPlaceName(to location: CLLocation) async -> String {
    if let station = await nearestStation(to: location) {
      return station.name
    }

    if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
      return placemark.name ?? placemark.locality ?? "現在地"
    }
    return "現在地"
  }

  /// The closest public-transport stop within the search radius, if one is close
  /// enough to be the place being passed.
  static func nearestStation(
    to location: CLLocation,
    radius: CLLocationDistance = 400
  ) async -> (name: String, location: CLLocation)? {
    let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: radius)
    request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.publicTransport])

    guard let response = try? await MKLocalSearch(request: request).start() else {
      return nil
    }

    return response.mapItems
      .compactMap { item -> (String, CLLocation)? in
        guard let name = item.name, let place = item.placemark.location else { return nil }
        return (name, place)
      }
      .min(by: { $0.1.distance(from: location) < $1.1.distance(from: location) })
      .map { ($0.0, $0.1) }
  }

  /// A station name without a doubled "駅", for wording like "渋谷駅付近を通過".
  static func stationNameWithoutSuffix(_ name: String) -> String {
    name.hasSuffix("駅") ? String(name.dropLast()) : name
  }
}
