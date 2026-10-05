import Foundation

@main
struct JournalPlaceChecks {
  static func main() {
    precondition(JournalPlace(name: "旧記録", latitude: nil, longitude: nil) == nil)
    precondition(JournalPlace(name: "欠落", latitude: 35, longitude: nil) == nil)
    precondition(JournalPlace(name: "範囲外", latitude: 91, longitude: 139) == nil)
    precondition(JournalPlace(name: "範囲外", latitude: 35, longitude: -181) == nil)
    precondition(JournalPlace(name: "不正", latitude: .nan, longitude: 139) == nil)
    precondition(JournalPlace(name: "不正", latitude: 35, longitude: .infinity) == nil)
    let place = JournalPlace(name: "東京駅", latitude: 35.681, longitude: 139.767)
    precondition(place?.name == "東京駅")
    precondition(place?.coordinate.latitude == 35.681)
    precondition(place?.coordinate.longitude == 139.767)
    precondition(JournalPlace(name: "境界", latitude: -90, longitude: 180) != nil)
    print("JournalPlace checks passed")
  }
}
