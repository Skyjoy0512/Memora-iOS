import Foundation

/// Stop at a settled chunk boundary instead of holding an audio session or
/// retrying expensive recognition while the OS reports thermal pressure.
enum AudioProcessingReadiness {
  static func check(thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState) throws {
    try Task.checkCancellation()
    switch thermalState {
    case .nominal, .fair: return
    case .serious, .critical:
      AudioProcessingDiagnostics.current?.sample(.init(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
        thermalState: thermalState.rawValue))
      AudioProcessingDiagnostics.current?.finish(.deferred)
      throw SourceMediaFailure.thermalDeferred
    @unknown default:
      AudioProcessingDiagnostics.current?.finish(.deferred)
      throw SourceMediaFailure.thermalDeferred
    }
  }
}
