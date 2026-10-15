import Foundation
import Darwin

enum MCPPublicAddressPolicy {
  static func isPublic(_ text: String) -> Bool {
    var ipv4 = in_addr()
    if inet_pton(AF_INET, text, &ipv4) == 1 {
      let value = UInt32(bigEndian: ipv4.s_addr)
      let first = value >> 24, second = (value >> 16) & 255
      return first != 0 && first != 10 && first != 127 && first < 224 &&
        !(first == 100 && (64...127).contains(second)) &&
        !(first == 169 && second == 254) && !(first == 172 && (16...31).contains(second)) &&
        first != 192 && !(first == 198 && (18...19).contains(second)) &&
        !(first == 198 && second == 51) && !(first == 203 && second == 0)
    }
    var ipv6 = in6_addr()
    guard inet_pton(AF_INET6, text, &ipv6) == 1 else { return false }
    return withUnsafeBytes(of: &ipv6) { bytes in
      // Only global unicast; exclude documentation and transition networks.
      guard bytes[0] & 0xe0 == 0x20, !(bytes[0] == 0x20 && bytes[1] == 0x02) else { return false }
      if bytes[0] == 0x3f && bytes[1] == 0xff && bytes[2] & 0xf0 == 0 { return false }
      if bytes[0] == 0x20 && bytes[1] == 0x01 {
        return bytes[2] > 1 && !(bytes[2] == 0x0d && bytes[3] == 0xb8)
      }
      return true
    }
  }

  static func validateHost(_ host: String) async throws {
    _ = try await validatedAddresses(for: host)
  }

  static func validatedAddresses(for host: String) async throws -> [String] {
    let lookup = MCPDNSLookup<[String]>()
    let addresses = await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        lookup.install(continuation)
        Task.detached(priority: .utility) { lookup.finish(resolve(host)) }
      }
    } onCancel: { lookup.finish([]) }
    try Task.checkCancellation()
    guard !addresses.isEmpty else { throw MCPClientError.invalidURL }
    return addresses
  }

  private static func resolve(_ host: String) -> [String] {
      var hints = addrinfo()
      hints.ai_family = AF_UNSPEC
      hints.ai_socktype = SOCK_STREAM
      var result: UnsafeMutablePointer<addrinfo>?
      guard getaddrinfo(host, "443", &hints, &result) == 0, let result else { return [] }
      defer { freeaddrinfo(result) }
      var current: UnsafeMutablePointer<addrinfo>? = result
      var count = 0
      var addresses: [String] = []
      while let address = current {
        count += 1
        guard count <= 64 else { return [] }
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(address.pointee.ai_addr, address.pointee.ai_addrlen,
                          &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0,
              isPublic(String(cString: buffer)) else { return [] }
        let text = String(cString: buffer)
        if !addresses.contains(text) { addresses.append(text) }
        current = address.pointee.ai_next
      }
      return addresses
  }
}
