import Foundation
import Synchronization

/// Fail-closed URLProtocol: even a misconfigured endpoint cannot bypass the
/// budget broker. Only uncredentialed request data is put on the private pipe.
final class NativeSummaryWire: URLProtocol, @unchecked Sendable {
  private static let pending = Mutex<[String: NativeSummaryWire]>([:])
  private static let output = NSLock()
  private let identifier = UUID().uuidString
  private let state = NSRecursiveLock()
  private var settled = false

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    var bytes = request.httpBody
    if bytes == nil, let stream = request.httpBodyStream {
      stream.open(); defer { stream.close() }
      var body = Data(), buffer = [UInt8](repeating: 0, count: 4096)
      while true {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count >= 0, body.count + count <= 4 * 1_048_576 else { finish(error: URLError(.dataLengthExceedsMaximum)); return }
        if count == 0 { break }
        body.append(contentsOf: buffer.prefix(count))
      }
      bytes = body
    }
    guard let bytes, let object = try? JSONSerialization.jsonObject(with: bytes),
          let endpoint = request.url?.absoluteString, request.httpMethod == "POST" else {
      finish(error: URLError(.badURL)); return
    }
    Self.pending.withLock { $0[identifier] = self }
    Self.emit(["kind": "request", "id": identifier, "endpoint": endpoint, "body": object])
  }
  override func stopLoading() {
    state.lock(); settled = true; state.unlock()
    Self.pending.withLock { _ = $0.removeValue(forKey: identifier) }
    Self.emit(["kind": "cancel", "id": identifier])
  }
  static func emit(_ event: [String: Any]) {
    output.lock(); defer { output.unlock() }
    guard let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) else { return }
    FileHandle.standardOutput.write(data + Data([10]))
  }
  static func startReader() {
    DispatchQueue.global(qos: .utility).async {
      while let line = readLine(strippingNewline: true), let data = line.data(using: .utf8) {
        guard data.count <= 2 * 1_048_576,
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = event["id"] as? String, let target = pending.withLock({ $0[id] }) else { continue }
        target.receive(event)
      }
      let abandoned = pending.withLock { value in let all = Array(value.values); value.removeAll(); return all }
      for target in abandoned { target.finish(error: URLError(.networkConnectionLost)) }
    }
  }
  private func receive(_ event: [String: Any]) {
    state.lock(); defer { state.unlock() }
    guard !settled else { return }
    switch event["kind"] as? String {
    case "headers":
      guard let url = request.url, let status = event["status"] as? Int,
            let headers = event["headers"] as? [String: String],
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
        finish(error: URLError(.badServerResponse)); return
      }
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    case "bytes":
      guard let base64 = event["data"] as? String, let data = Data(base64Encoded: base64) else { finish(error: URLError(.cannotDecodeContentData)); return }
      client?.urlProtocol(self, didLoad: data)
    case "end": finish(error: nil)
    default: finish(error: URLError(event["timedOut"] as? Bool == true ? .timedOut : .networkConnectionLost))
    }
  }
  private func finish(error: Error?) {
    state.lock(); defer { state.unlock() }
    guard !settled else { return }
    settled = true
    Self.pending.withLock { _ = $0.removeValue(forKey: identifier) }
    if let error { client?.urlProtocol(self, didFailWithError: error) }
    else { client?.urlProtocolDidFinishLoading(self) }
  }
}
