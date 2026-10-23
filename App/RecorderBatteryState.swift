import Foundation

/// A Battery Service reading belongs only to the current connection, never a
/// remembered device or the iPhone's own battery.
struct RecorderBatteryState: Equatable {
  static let serviceUUID = "180F"
  static let characteristicUUID = "2A19"
  private(set) var deviceID: UUID?
  private(set) var percentage: Int?

  mutating func connected(to id: UUID) {
    deviceID = id
    percentage = nil
  }

  mutating func disconnected(from id: UUID) {
    guard deviceID == id else { return }
    deviceID = nil
    percentage = nil
  }

  mutating func receive(_ data: Data?, from id: UUID) {
    guard deviceID == id else { return }
    guard let data, data.count == 1, let value = data.first, value <= 100 else {
      percentage = nil
      return
    }
    percentage = Int(value)
  }
}
