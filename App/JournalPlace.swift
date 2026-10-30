import CoreLocation

struct JournalPlace: Codable, Equatable {
  var name: String
  var latitude: Double
  var longitude: Double

  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  init?(name: String, latitude: Double?, longitude: Double?) {
    guard let latitude, let longitude, latitude.isFinite, longitude.isFinite,
          (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
    self.name = name
    self.latitude = latitude
    self.longitude = longitude
  }
}
