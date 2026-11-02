import Foundation

/// This schema deliberately has no content, path, record ID, endpoint or error
/// string field. Trace IDs are fresh random IDs unrelated to saved records.
struct AudioDiagnosticReport: Codable, Identifiable, Sendable {
  enum Kind: String, Codable, Sendable {
    case recording, liveTranscription, recordedTranscription, sourceExtraction, cloudTranscription, speakerAnalysis, voiceActivity, quality, summary
  }
  enum Stage: String, Codable, Sendable {
    case queue, snapshot, exportAudio, modelPreparation, recognition, upload, decode, quality, vad, diarization, summary, verification
  }
  enum Outcome: String, Codable, Sendable {
    case running, success, empty, failed, cancelled, unavailable, interrupted, deferred
  }
  enum Engine: String, Codable, Sendable {
    case appleSpeech, openAIWhisper, deepgramNova3, fluidSpeaker, silero, onDeviceSummary, cloudSummary
  }
  enum Counter: String, Codable, Sendable {
    case recordingPause, recordingResume, audioInterruption, inputLost, audioReset, storageStop, liveBufferDropped
  }
  struct Event: Codable, Sendable {
    var stage: Stage
    var elapsedSeconds: Double
    var wallSeconds: Double?
    var audioSeconds: Double?
    var outcome: Outcome
  }
  struct Total: Codable, Sendable {
    var calls = 0
    var wallSeconds = 0.0
    var audioSeconds = 0.0
    var successfulAudioSeconds = 0.0
    var successfulWallSeconds = 0.0
    var successfulCalls = 0
    var rtf: Double? { successfulAudioSeconds > 0 ? successfulWallSeconds / successfulAudioSeconds : nil }
  }
  struct Resources: Codable, Sendable {
    var elapsedSeconds: Double = 0
    var footprintBytes: UInt64?
    var batteryFraction: Double?
    var charging: Bool?
    var lowPower: Bool
    var thermalState: Int
  }
  var schemaVersion = 1
  var id: UUID
  var revision = 0
  var kind: Kind
  var engine: Engine?
  var environment: AudioDiagnosticEnvironment
  var includesSignalInspection = false
  var outcome: Outcome = .running
  var wallSeconds = 0.0
  var audioSeconds: Double?
  var reusedChunks = 0
  var completedChunks = 0
  var events: [Event] = []
  var omittedEvents = 0
  var totals: [String: Total] = [:]
  var samples: [Resources] = []
  var omittedSamples = 0
  var sampledPeakFootprintBytes: UInt64?
  var firstBatteryFraction: Double?
  var lastBatteryFraction: Double?
  var maximumThermalState = 0
  var signals: [AudioSignalReport] = []
  var counters: [String: Int] = [:]

  var overallRTF: Double? {
    guard outcome == .success || outcome == .empty, kind != .recording, kind != .liveTranscription else { return nil }
    return audioSeconds.flatMap { $0 > 0 ? wallSeconds / $0 : nil }
  }

  var isValid: Bool {
    guard schemaVersion == 1, environment.isValid, revision >= 0,
          wallSeconds.isFinite, wallSeconds >= 0, events.count <= 256, samples.count <= 256,
          omittedEvents >= 0, omittedSamples >= 0, (0...3).contains(maximumThermalState),
          [firstBatteryFraction, lastBatteryFraction].allSatisfy({ $0.map { $0.isFinite && (0...1).contains($0) } ?? true }),
          reusedChunks >= 0, completedChunks >= 0, signals.count <= 128, signals.allSatisfy(\.isValid),
          totals.keys.allSatisfy({ Stage(rawValue: $0) != nil }),
          counters.allSatisfy({ Counter(rawValue: $0.key) != nil && $0.value >= 0 }),
          audioSeconds.map({ $0.isFinite && $0 > 0 }) ?? true else { return false }
    return events.allSatisfy {
      $0.elapsedSeconds.isFinite && $0.elapsedSeconds >= 0 &&
        ($0.wallSeconds.map { $0.isFinite && $0 >= 0 } ?? true) &&
        ($0.audioSeconds.map { $0.isFinite && $0 > 0 } ?? true)
    } && totals.values.allSatisfy {
      $0.calls >= 0 && $0.wallSeconds.isFinite && $0.wallSeconds >= 0 &&
        $0.audioSeconds.isFinite && $0.audioSeconds >= 0 &&
        $0.successfulAudioSeconds.isFinite && $0.successfulAudioSeconds >= 0 && $0.successfulAudioSeconds <= $0.audioSeconds &&
        $0.successfulWallSeconds.isFinite && $0.successfulWallSeconds >= 0 && $0.successfulWallSeconds <= $0.wallSeconds &&
        $0.successfulCalls >= 0 && $0.successfulCalls <= $0.calls
    } && samples.allSatisfy {
      $0.elapsedSeconds.isFinite && $0.elapsedSeconds >= 0 && (0...3).contains($0.thermalState) &&
        ($0.batteryFraction.map { $0.isFinite && (0...1).contains($0) } ?? true)
    }
  }
}
