import Foundation
import Compression

/// Reads selected package parts in memory. No archive path is ever written to disk.
struct OfficeArchiveReader {
  static let maximumArchiveBytes = 50 * 1024 * 1024
  static let maximumPartBytes = 2 * 1024 * 1024
  static let maximumReadBytes = 8 * 1024 * 1024
  private var bytes: Data
  private var entries: [String: Entry] = [:]
  private var readBytes = 0

  enum Failure: LocalizedError {
    case invalid, limit, unsupported
    var errorDescription: String? {
      switch self {
      case .invalid: "Officeファイルの構造を読み取れませんでした。元ファイルは保存されています。"
      case .limit: "安全に解析できるOfficeファイルの上限を超えています。PDFやテキストに書き出して追加してください。"
      case .unsupported: "このOfficeファイルの暗号化・圧縮形式には対応していません。PDFやテキストに書き出して追加してください。"
      }
    }
  }

  init(url: URL) throws {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: Self.maximumArchiveBytes + 1) ?? Data()
    try self.init(data: data)
  }

  init(data: Data) throws {
    guard data.count <= Self.maximumArchiveBytes else { throw Failure.limit }
    bytes = data
    guard data.count >= 22 else { throw Failure.invalid }
    var end: Int?
    for offset in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
      if try u32(offset) == 0x0605_4b50,
         try offset + 22 + u16(offset + 20) == data.count { end = offset; break }
    }
    guard let end else { throw Failure.invalid }
    let count = try u16(end + 10)
    guard try u16(end + 4) == 0, try u16(end + 6) == 0,
          try u16(end + 8) == count, count > 0, count < 65_535 else { throw Failure.unsupported }
    guard count <= 2_048 else { throw Failure.limit }
    let directory = try u32(end + 16)
    let directorySize = try u32(end + 12)
    guard directory + directorySize == end else { throw Failure.invalid }
    var cursor = directory
    var regions: [Range<Int>] = []
    var names: Set<String> = []
    var declaredBytes = 0
    for _ in 0..<count {
      try Task.checkCancellation()
      guard cursor + 46 <= end, try u32(cursor) == 0x0201_4b50 else { throw Failure.invalid }
      let flags = try u16(cursor + 8), method = try u16(cursor + 10)
      guard try u16(cursor + 6) < 45, try u16(cursor + 34) == 0,
            flags & ~0x080e == 0, method == 0 || method == 8 else { throw Failure.unsupported }
      let crc = UInt32(try u32(cursor + 16))
      let compressed = try u32(cursor + 20), expanded = try u32(cursor + 24)
      declaredBytes += expanded
      guard declaredBytes <= 128 * 1024 * 1024 else { throw Failure.limit }
      let nameSize = try u16(cursor + 28)
      let next = try cursor + 46 + nameSize + u16(cursor + 30) + u16(cursor + 32)
      guard next <= end, nameSize > 0,
            let name = String(data: bytes.subdata(in: cursor + 46..<cursor + 46 + nameSize), encoding: .utf8),
            Self.safePath(name), names.insert(name.lowercased()).inserted else { throw Failure.invalid }
      let unixKind = try (u32(cursor + 38) >> 16) & 0xf000
      guard [0, 0x8000, 0x4000].contains(unixKind) else { throw Failure.unsupported }
      let local = try u32(cursor + 42)
      guard local + 30 <= directory, try u32(local) == 0x0403_4b50,
            try u16(local + 6) == flags, try u16(local + 8) == method,
            try u16(local + 26) == nameSize else { throw Failure.invalid }
      let payload = try local + 30 + nameSize + u16(local + 28)
      var payloadEnd = payload + compressed
      guard payloadEnd <= directory,
            bytes.subdata(in: local + 30..<local + 30 + nameSize) == Data(name.utf8) else { throw Failure.invalid }
      if flags & 8 == 0 {
        guard try u32(local + 14) == Int(crc), try u32(local + 18) == compressed,
              try u32(local + 22) == expanded else { throw Failure.invalid }
      } else {
        // Streaming ZIP writers put sizes in the data descriptor, after the payload.
        if try u32(payloadEnd) == 0x0807_4b50 { payloadEnd += 4 }
        guard payloadEnd + 12 <= directory, try u32(payloadEnd) == Int(crc),
              try u32(payloadEnd + 4) == compressed, try u32(payloadEnd + 8) == expanded else { throw Failure.invalid }
        payloadEnd += 12
      }
      regions.append(local..<payloadEnd)
      entries[name] = Entry(range: payload..<payload + compressed, expanded: expanded, method: method, crc: crc)
      cursor = next
    }
    guard cursor == end else { throw Failure.invalid }
    let sorted = regions.sorted { $0.lowerBound < $1.lowerBound }
    for index in 1..<sorted.count {
      guard sorted[index - 1].upperBound <= sorted[index].lowerBound else { throw Failure.invalid }
    }
  }

  var partNames: [String] { entries.keys.sorted() }

  func contains(_ name: String) -> Bool { entries[name] != nil }

  mutating func read(_ name: String) throws -> Data {
    try Task.checkCancellation()
    guard let entry = entries[name] else { throw Failure.invalid }
    guard entry.expanded <= Self.maximumPartBytes, entry.range.count <= Self.maximumPartBytes + 64 * 1024,
          readBytes + entry.expanded <= Self.maximumReadBytes else { throw Failure.limit }
    readBytes += entry.expanded
    let source = bytes.subdata(in: entry.range)
    let output: Data
    if entry.method == 0 {
      guard source.count == entry.expanded else { throw Failure.invalid }
      output = source
    } else {
      // Apple's ZLIB algorithm consumes raw RFC 1951 DEFLATE, as ZIP requires.
      var expanded = Data(count: entry.expanded + 1)
      let expectedSize = entry.expanded
      let decoded = expanded.withUnsafeMutableBytes { destination in
        source.withUnsafeBytes { input -> Bool in
          guard let src = input.bindMemory(to: UInt8.self).baseAddress,
                let dst = destination.bindMemory(to: UInt8.self).baseAddress else { return false }
          var stream = compression_stream(dst_ptr: dst, dst_size: destination.count,
            src_ptr: src, src_size: input.count, state: nil)
          guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return false }
          defer { compression_stream_destroy(&stream) }
          stream.src_ptr = src; stream.src_size = input.count
          stream.dst_ptr = dst; stream.dst_size = destination.count
          // A decoder can consume all input before delivering its buffered
          // output. Drain it, requiring progress and bounding work each time.
          for _ in 0..<256 {
            if Task.isCancelled { return false }
            let previousSource = stream.src_size, previousDestination = stream.dst_size
            let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
            if status == COMPRESSION_STATUS_END {
              return stream.src_size == 0 && destination.count - stream.dst_size == expectedSize
            }
            guard status == COMPRESSION_STATUS_OK, stream.dst_size > 0,
                  stream.src_size < previousSource || stream.dst_size < previousDestination else { return false }
          }
          return false
        }
      }
      try Task.checkCancellation()
      guard decoded else { throw Failure.invalid }
      expanded.removeLast()
      output = expanded
    }
    try Task.checkCancellation()
    guard ZipArchive.crc32(output) == entry.crc else { throw Failure.invalid }
    return output
  }

  private static func safePath(_ name: String) -> Bool {
    guard !name.hasPrefix("/"), !name.contains("\\"),
          !name.unicodeScalars.contains(where: { $0.value < 32 }),
          !name.contains(":"), !name.contains("%"), !name.contains("?"), !name.contains("#") else { return false }
    let parts = name.split(separator: "/", omittingEmptySubsequences: false)
    return parts.enumerated().allSatisfy { index, part in
      part != "." && part != ".." && (!part.isEmpty || index == parts.count - 1)
    }
  }

  private func u16(_ offset: Int) throws -> Int {
    guard offset >= 0, offset + 2 <= bytes.count else { throw Failure.invalid }
    return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
  }

  private func u32(_ offset: Int) throws -> Int {
    guard offset >= 0, offset + 4 <= bytes.count else { throw Failure.invalid }
    return try u16(offset) | u16(offset + 2) << 16
  }

  private struct Entry {
    var range: Range<Int>
    var expanded: Int
    var method: Int
    var crc: UInt32
  }
}
