import os

/// Static signpost names contain no audio, transcript, record ID or credential.
enum AudioProcessingDiagnostics {
  static let signposter = OSSignposter(subsystem: "app.memora.audio", category: "Processing")
}
