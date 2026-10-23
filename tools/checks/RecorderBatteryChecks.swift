import Foundation

@main
struct RecorderBatteryChecks {
  static func main() {
    let first = UUID()
    let second = UUID()
    var battery = RecorderBatteryState()
    precondition(battery.deviceID == nil && battery.percentage == nil)
    battery.receive(Data([85]), from: first)
    precondition(battery.percentage == nil)
    battery.connected(to: first)
    for value in UInt8.min...UInt8.max {
      battery.receive(Data([value]), from: first)
      precondition(battery.percentage == (value <= 100 ? Int(value) : nil))
    }
    battery.receive(Data([50]), from: first)
    battery.receive(Data([90]), from: second)
    precondition(battery.percentage == 50)
    battery.disconnected(from: second)
    precondition(battery.percentage == 50)
    for invalid in [nil, Data(), Data([60, 10])] as [Data?] {
      battery.receive(invalid, from: first)
      precondition(battery.percentage == nil)
    }
    battery.receive(Data([100]), from: first)
    battery.connected(to: second)
    precondition(battery.percentage == nil)
    battery.receive(Data([55]), from: first)
    precondition(battery.percentage == nil)
    battery.receive(Data([0]), from: second)
    precondition(battery.percentage == 0)
    battery.disconnected(from: second)
    precondition(battery.percentage == nil && battery.deviceID == nil)
    battery.receive(Data([50]), from: second)
    precondition(battery.percentage == nil)
    precondition(RecorderBatteryState.serviceUUID == "180F" && RecorderBatteryState.characteristicUUID == "2A19")
    print("Recorder battery checks passed: all 256 byte values, invalid data, identity, reconnect and disconnect")
  }
}
