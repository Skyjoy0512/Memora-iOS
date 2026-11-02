import Darwin
import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum AudioResourceProbe {
  static func capture() async -> AudioDiagnosticReport.Resources {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
      }
    }
    #if canImport(UIKit)
    let battery = await AudioBatteryProbe.read()
    #else
    let battery: (Double?, Bool?) = (nil, nil)
    #endif
    return .init(footprintBytes: result == KERN_SUCCESS ? info.phys_footprint : nil,
      batteryFraction: battery.0, charging: battery.1,
      lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
      thermalState: ProcessInfo.processInfo.thermalState.rawValue)
  }

  static func acquireBattery(_ token: UUID) async {
    #if canImport(UIKit)
    await AudioBatteryProbe.acquire(token)
    #endif
  }

  static func releaseBattery(_ token: UUID) async {
    #if canImport(UIKit)
    await AudioBatteryProbe.release(token)
    #endif
  }
}

#if canImport(UIKit)
@MainActor private enum AudioBatteryProbe {
  private static var owners: Set<UUID> = []
  private static var wasEnabled = false
  static func acquire(_ token: UUID) {
    if owners.isEmpty {
      wasEnabled = UIDevice.current.isBatteryMonitoringEnabled
      UIDevice.current.isBatteryMonitoringEnabled = true
    }
    owners.insert(token)
  }
  static func release(_ token: UUID) {
    guard owners.remove(token) != nil, owners.isEmpty else { return }
    UIDevice.current.isBatteryMonitoringEnabled = wasEnabled
  }
  static func read() -> (Double?, Bool?) {
    let device = UIDevice.current
    let level = Double(device.batteryLevel)
    let charging: Bool? = switch device.batteryState {
    case .charging, .full: true
    case .unplugged: false
    default: nil
    }
    return ((0...1).contains(level) ? level : nil, charging)
  }
}
#endif
