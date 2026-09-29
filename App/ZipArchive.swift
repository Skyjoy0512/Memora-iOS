import Foundation

/// Writes a ZIP archive with its entries stored uncompressed. Office files are
/// ZIP packages; stored entries are valid in every reader and need no
/// compression library.
struct ZipArchive {
  private var entries: [(name: String, data: Data)] = []

  mutating func add(_ name: String, data: Data) {
    entries.append((name, data))
  }

  mutating func add(_ name: String, text: String) {
    add(name, data: Data(text.utf8))
  }

  func data() -> Data {
    var archive = Data()
    var directory = Data()

    for entry in entries {
      let name = Data(entry.name.utf8)
      let crc = Self.crc32(entry.data)
      let size = UInt32(entry.data.count)
      let offset = UInt32(archive.count)

      // Local file header.
      archive.appendLittleEndian(UInt32(0x0403_4b50))
      archive.appendLittleEndian(UInt16(20))       // version needed
      archive.appendLittleEndian(UInt16(0x0800))   // UTF-8 names
      archive.appendLittleEndian(UInt16(0))        // stored
      archive.appendLittleEndian(UInt16(0))        // time
      archive.appendLittleEndian(UInt16(0x0021))   // date: 1980-01-01
      archive.appendLittleEndian(crc)
      archive.appendLittleEndian(size)
      archive.appendLittleEndian(size)
      archive.appendLittleEndian(UInt16(name.count))
      archive.appendLittleEndian(UInt16(0))
      archive.append(name)
      archive.append(entry.data)

      // Its central directory record.
      directory.appendLittleEndian(UInt32(0x0201_4b50))
      directory.appendLittleEndian(UInt16(20))     // version made by
      directory.appendLittleEndian(UInt16(20))     // version needed
      directory.appendLittleEndian(UInt16(0x0800))
      directory.appendLittleEndian(UInt16(0))
      directory.appendLittleEndian(UInt16(0))
      directory.appendLittleEndian(UInt16(0x0021))
      directory.appendLittleEndian(crc)
      directory.appendLittleEndian(size)
      directory.appendLittleEndian(size)
      directory.appendLittleEndian(UInt16(name.count))
      directory.appendLittleEndian(UInt16(0))      // extra
      directory.appendLittleEndian(UInt16(0))      // comment
      directory.appendLittleEndian(UInt16(0))      // disk
      directory.appendLittleEndian(UInt16(0))      // internal attributes
      directory.appendLittleEndian(UInt32(0))      // external attributes
      directory.appendLittleEndian(offset)
      directory.append(name)
    }

    let directoryOffset = UInt32(archive.count)
    archive.append(directory)

    // End of central directory.
    archive.appendLittleEndian(UInt32(0x0605_4b50))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(0))
    archive.appendLittleEndian(UInt16(entries.count))
    archive.appendLittleEndian(UInt16(entries.count))
    archive.appendLittleEndian(UInt32(directory.count))
    archive.appendLittleEndian(directoryOffset)
    archive.appendLittleEndian(UInt16(0))
    return archive
  }

  private static let crcTable: [UInt32] = (0..<256).map { index in
    var value = UInt32(index)
    for _ in 0..<8 {
      value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
    }
    return value
  }

  static func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
      crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
    }
    return crc ^ 0xFFFF_FFFF
  }
}

private extension Data {
  mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
    Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
  }
}
