import Foundation

@MainActor
final class JSONRenderEnvelopeCache {
  private var text: String?
  private var streaming = false
  private var cached: JSONRenderEnvelope?

  func response(for text: String, isStreaming: Bool) -> JSONRenderEnvelope? {
    if self.text == text, streaming == isStreaming { return cached }
    self.text = text
    streaming = isStreaming
    cached = JSONRenderEnvelope.parse(text, isStreaming: isStreaming)
    return cached
  }
}
