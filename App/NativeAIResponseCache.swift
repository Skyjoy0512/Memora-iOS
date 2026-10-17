import Foundation

/// A disposable rendering cache. It contains no conversation or access grants.
@MainActor
final class NativeAIResponseCache {
  private var previousText: String?
  private var previousStreaming = false
  private var stream = NativeAIComponentStream()
  private var cached: (markdown: String, interface: NativeAIInterface?) = ("", nil)

  func response(for text: String, isStreaming: Bool) -> (markdown: String, interface: NativeAIInterface?) {
    if previousText == text && previousStreaming == isStreaming { return cached }
    if let previousText, !text.hasPrefix(previousText) { stream = NativeAIComponentStream() }
    previousText = text; previousStreaming = isStreaming
    cached = NativeAIInterface.response(text, isStreaming: isStreaming, stream: &stream)
    return cached
  }
}
