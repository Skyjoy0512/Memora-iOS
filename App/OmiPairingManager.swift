import CoreBluetooth
import Foundation
import Observation

@Observable
final class OmiPairingManager: NSObject {
  struct Device: Identifiable, Equatable {
    var id: UUID
    var name: String
    var signalStrength: Int
  }

  /// What the connected device reports about itself.
  struct DeviceDetails: Equatable {
    var identifier: UUID
    var name: String
    var model: String?
    var manufacturer: String?
    var firmwareVersion: String?
  }

  enum ConnectionState: Equatable {
    case idle
    case remembered(String)
    case preparing
    case scanning
    case scanFinished
    case connecting(String)
    case connected(String)
    case bluetoothOff
    case unauthorized
    case unsupported
    case failed(String)

    var shortLabel: String {
      switch self {
      case .idle:
        "未接続"
      case .remembered:
        "前回のデバイス"
      case .preparing:
        "準備中"
      case .scanning:
        "検索中"
      case .scanFinished:
        "検索完了"
      case .connecting:
        "接続中"
      case .connected:
        "接続済み"
      case .bluetoothOff:
        "Bluetoothオフ"
      case .unauthorized:
        "アクセス未許可"
      case .unsupported:
        "実機のみ"
      case .failed:
        "接続できません"
      }
    }
  }

  private(set) var state: ConnectionState
  private(set) var devices: [Device] = []
  /// Populated once a device is connected and it reports its own details.
  private(set) var details: DeviceDetails?
  private(set) var batteryState = RecorderBatteryState()

  @ObservationIgnored private var centralManager: CBCentralManager?
  @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
  @ObservationIgnored private var connectedPeripheral: CBPeripheral?
  @ObservationIgnored private var connectingPeripheralID: UUID?
  /// True only while someone is looking for a device. Bluetooth coming back on
  /// must not start a scan by itself.
  @ObservationIgnored private var wantsScanning = false
  @ObservationIgnored private var scanDeadline: DispatchWorkItem?
  #if DEBUG
  @ObservationIgnored private var isReview = false
  #endif

  private static let audioService = CBUUID(string: "19B10000-E8F2-537E-4F6C-D104768A1214")
  private static let deviceInformationService = CBUUID(string: "180A")
  private static let firmwareRevisionCharacteristic = CBUUID(string: "2A26")
  private static let modelNumberCharacteristic = CBUUID(string: "2A24")
  private static let manufacturerNameCharacteristic = CBUUID(string: "2A29")
  private static let batteryService = CBUUID(string: RecorderBatteryState.serviceUUID)
  private static let batteryLevelCharacteristic = CBUUID(string: RecorderBatteryState.characteristicUUID)
  private static let rememberedNameKey = "omiRememberedDeviceName"

  /// True once an external recorder has been paired, even if none is connected
  /// now, so its shortcut can stay out of the way for people who have none.
  static var hasRememberedDevice: Bool {
    UserDefaults.standard.string(forKey: rememberedNameKey) != nil
  }

  override init() {
    if let rememberedName = UserDefaults.standard.string(forKey: Self.rememberedNameKey) {
      state = .remembered(rememberedName)
    } else {
      state = .idle
    }
    super.init()
  }

  #if DEBUG
  convenience init(reviewState: ConnectionState) {
    self.init()
    isReview = true
    state = reviewState
    if reviewState == .scanning { startScanning() }
  }
  #endif

  func startScanning() {
    #if DEBUG
    if isReview {
      wantsScanning = true
      state = .scanning
      scheduleScanDeadline()
      return
    }
    #endif
    #if targetEnvironment(simulator)
    state = .unsupported
    #else
    cancelPairing()
    wantsScanning = true
    state = .preparing

    if let centralManager {
      beginScanIfPossible(using: centralManager)
    } else {
      centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    #endif
  }

  func cancelPairing() {
    wantsScanning = false
    scanDeadline?.cancel()
    scanDeadline = nil
    centralManager?.stopScan()
    let pending = connectingPeripheralID.flatMap { peripherals[$0] }
    connectingPeripheralID = nil
    if let pending {
      centralManager?.cancelPeripheralConnection(pending)
    }
    devices = []
    releaseUnconnectedPeripherals()
    switch state {
    case .preparing, .scanning, .scanFinished, .connecting:
      state = rememberedState
    default:
      break
    }
  }

  func connect(to device: Device) {
    guard state == .scanning || state == .scanFinished else { return }
    guard let peripheral = peripherals[device.id], let centralManager else { return }
    if let previous = connectedPeripheral { centralManager.cancelPeripheralConnection(previous) }
    connectedPeripheral = nil
    details = nil
    batteryState = RecorderBatteryState()
    connectingPeripheralID = peripheral.identifier
    wantsScanning = false
    scanDeadline?.cancel()
    scanDeadline = nil
    centralManager.stopScan()
    state = .connecting(device.name)
    centralManager.connect(peripheral)
  }

  func disconnect() {
    cancelPairing()
    if let connectedPeripheral, let centralManager {
      centralManager.cancelPeripheralConnection(connectedPeripheral)
    }
    wantsScanning = false
    connectedPeripheral = nil
    connectingPeripheralID = nil
    details = nil
    batteryState = RecorderBatteryState()
    peripherals = [:]
    devices = []
    UserDefaults.standard.removeObject(forKey: Self.rememberedNameKey)
    state = .idle
  }

  /// Frees the discovered peripherals once they are no longer being looked at,
  /// so a scan does not keep every device it saw.
  private func releaseUnconnectedPeripherals() {
    guard let connectedPeripheral else {
      peripherals = [:]
      return
    }
    peripherals = [connectedPeripheral.identifier: connectedPeripheral]
  }

  private var rememberedState: ConnectionState {
    if let rememberedName = UserDefaults.standard.string(forKey: Self.rememberedNameKey) {
      .remembered(rememberedName)
    } else {
      .idle
    }
  }

  private func beginScanIfPossible(using central: CBCentralManager) {
    guard wantsScanning else {
      guard connectedPeripheral == nil, connectingPeripheralID == nil else { return }
      state = availabilityState(for: central)
      return
    }
    guard central.state == .poweredOn else {
      if central.state != .unknown, central.state != .resetting {
        wantsScanning = false
      }
      state = availabilityState(for: central)
      return
    }
    state = .scanning
    central.scanForPeripherals(
      withServices: [Self.audioService],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
    scheduleScanDeadline()
  }

  private func scheduleScanDeadline() {
    scanDeadline?.cancel()
    let deadline = DispatchWorkItem { [weak self] in
      guard let self, self.wantsScanning, self.state == .scanning else { return }
      // Retain the results so a person can still select a device after the scan.
      self.wantsScanning = false
      self.centralManager?.stopScan()
      self.scanDeadline = nil
      self.state = .scanFinished
    }
    scanDeadline = deadline
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(15), execute: deadline)
  }

  /// What to say about Bluetooth without starting anything.
  private func availabilityState(for central: CBCentralManager) -> ConnectionState {
    switch central.state {
    case .poweredOn:
      rememberedState
    case .poweredOff:
      .bluetoothOff
    case .unauthorized:
      .unauthorized
    case .unsupported:
      .unsupported
    case .resetting, .unknown:
      .preparing
    @unknown default:
      .failed("Bluetoothの状態を確認できませんでした。")
    }
  }
}

extension OmiPairingManager: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state != .poweredOn {
      if wantsScanning, central.state == .unknown || central.state == .resetting {
        state = .preparing
        return
      }
      cancelPairing()
      batteryState = RecorderBatteryState()
      connectedPeripheral = nil
      details = nil
      peripherals = [:]
      state = availabilityState(for: central)
      return
    }
    beginScanIfPossible(using: central)
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    guard wantsScanning, state == .scanning else { return }
    let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
    let name = peripheral.name ?? advertisedName ?? "Omi"
    let device = Device(id: peripheral.identifier, name: name, signalStrength: RSSI.intValue)
    peripherals[peripheral.identifier] = peripheral

    if let index = devices.firstIndex(where: { $0.id == device.id }) {
      devices[index] = device
    } else {
      devices.append(device)
      devices.sort { $0.signalStrength > $1.signalStrength }
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    guard connectingPeripheralID == peripheral.identifier else {
      central.cancelPeripheralConnection(peripheral)
      return
    }
    connectingPeripheralID = nil
    connectedPeripheral = peripheral
    batteryState.connected(to: peripheral.identifier)
    let name = peripheral.name ?? "Omi"
    UserDefaults.standard.set(name, forKey: Self.rememberedNameKey)
    details = DeviceDetails(identifier: peripheral.identifier, name: name)
    peripheral.delegate = self
    // The Device Information service carries the firmware revision, model and
    // manufacturer the details screen shows.
    peripheral.discoverServices([Self.deviceInformationService, Self.audioService, Self.batteryService])
    state = .connected(name)
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    guard connectingPeripheralID == peripheral.identifier else { return }
    connectingPeripheralID = nil
    batteryState = RecorderBatteryState()
    peripherals[peripheral.identifier] = nil
    state = .failed(error?.localizedDescription ?? "Omiへ接続できませんでした。")
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    guard connectedPeripheral === peripheral else { return }
    batteryState.disconnected(from: peripheral.identifier)
    connectedPeripheral = nil
    details = nil
    peripherals[peripheral.identifier] = nil
    if let error {
      state = .failed(error.localizedDescription)
    } else {
      state = rememberedState
    }
  }
}

extension OmiPairingManager: CBPeripheralDelegate {
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard connectedPeripheral === peripheral, error == nil, let services = peripheral.services else { return }
    for service in services {
      if service.uuid == Self.batteryService {
        peripheral.discoverCharacteristics([Self.batteryLevelCharacteristic], for: service)
      } else if service.uuid == Self.deviceInformationService {
        peripheral.discoverCharacteristics(
          [
            Self.firmwareRevisionCharacteristic,
            Self.modelNumberCharacteristic,
            Self.manufacturerNameCharacteristic
          ],
          for: service
        )
      }
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    guard connectedPeripheral === peripheral, error == nil, let characteristics = service.characteristics else { return }
    for characteristic in characteristics {
      switch characteristic.uuid {
      case Self.batteryLevelCharacteristic:
        guard service.uuid == Self.batteryService else { continue }
        if characteristic.properties.contains(.read) { peripheral.readValue(for: characteristic) }
        if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
          peripheral.setNotifyValue(true, for: characteristic)
        }
      case Self.firmwareRevisionCharacteristic,
        Self.modelNumberCharacteristic,
        Self.manufacturerNameCharacteristic:
        peripheral.readValue(for: characteristic)
      default:
        break
      }
    }
  }

  func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard connectedPeripheral === peripheral, case .connected = state else { return }
    if characteristic.uuid == Self.batteryLevelCharacteristic {
      guard characteristic.service?.uuid == Self.batteryService else { return }
      batteryState.receive(error == nil ? characteristic.value : nil, from: peripheral.identifier)
      return
    }
    guard error == nil, let data = characteristic.value else { return }
    let value = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }

    var updated = details ?? DeviceDetails(identifier: peripheral.identifier, name: peripheral.name ?? "Omi")
    switch characteristic.uuid {
    case Self.firmwareRevisionCharacteristic: updated.firmwareVersion = value
    case Self.modelNumberCharacteristic: updated.model = value
    case Self.manufacturerNameCharacteristic: updated.manufacturer = value
    default: return
    }
    details = updated
  }
}
