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

  @ObservationIgnored private var centralManager: CBCentralManager?
  @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
  @ObservationIgnored private var connectedPeripheral: CBPeripheral?
  /// True only while someone is looking for a device. Bluetooth coming back on
  /// must not start a scan by itself.
  @ObservationIgnored private var wantsScanning = false

  private static let audioService = CBUUID(string: "19B10000-E8F2-537E-4F6C-D104768A1214")
  private static let deviceInformationService = CBUUID(string: "180A")
  private static let firmwareRevisionCharacteristic = CBUUID(string: "2A26")
  private static let modelNumberCharacteristic = CBUUID(string: "2A24")
  private static let manufacturerNameCharacteristic = CBUUID(string: "2A29")
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

  func startScanning() {
    #if targetEnvironment(simulator)
    state = .unsupported
    #else
    wantsScanning = true
    devices = []
    peripherals = [:]
    state = .preparing

    if let centralManager {
      beginScanIfPossible(using: centralManager)
    } else {
      centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    #endif
  }

  func stopScanning() {
    wantsScanning = false
    centralManager?.stopScan()
    releaseUnconnectedPeripherals()
    if case .scanning = state {
      state = rememberedState
    }
  }

  func connect(to device: Device) {
    guard let peripheral = peripherals[device.id], let centralManager else { return }
    wantsScanning = false
    centralManager.stopScan()
    state = .connecting(device.name)
    centralManager.connect(peripheral)
  }

  func disconnect() {
    if let connectedPeripheral, let centralManager {
      centralManager.cancelPeripheralConnection(connectedPeripheral)
    }
    wantsScanning = false
    connectedPeripheral = nil
    details = nil
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
      state = availabilityState(for: central)
      return
    }
    guard central.state == .poweredOn else {
      state = availabilityState(for: central)
      return
    }
    state = .scanning
    central.scanForPeripherals(
      withServices: [Self.audioService],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
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
    beginScanIfPossible(using: central)
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
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
    connectedPeripheral = peripheral
    let name = peripheral.name ?? "Omi"
    UserDefaults.standard.set(name, forKey: Self.rememberedNameKey)
    details = DeviceDetails(identifier: peripheral.identifier, name: name)
    peripheral.delegate = self
    // The Device Information service carries the firmware revision, model and
    // manufacturer the details screen shows.
    peripheral.discoverServices([Self.deviceInformationService, Self.audioService])
    state = .connected(name)
  }

  func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    peripherals[peripheral.identifier] = nil
    state = .failed(error?.localizedDescription ?? "Omiへ接続できませんでした。")
  }

  func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
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
    guard error == nil, let services = peripheral.services else { return }
    for service in services where service.uuid == Self.deviceInformationService {
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

  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    guard error == nil, let characteristics = service.characteristics else { return }
    for characteristic in characteristics {
      switch characteristic.uuid {
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
