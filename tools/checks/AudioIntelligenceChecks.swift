import AVFoundation
import CoreML
import Foundation

@main struct AudioIntelligenceChecks {
  static func main() throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try AudioProcessingReadiness.check(thermalState: .nominal)
    try AudioProcessingReadiness.check(thermalState: .fair)
    for state: ProcessInfo.ThermalState in [.serious, .critical] {
      do {
        try AudioProcessingReadiness.check(thermalState: state)
        preconditionFailure("Thermal pressure accepted")
      } catch SourceMediaFailure.thermalDeferred { }
    }
    let url = root.appendingPathComponent("stereo.wav")
    let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 2)!
    do {
      let file = try AVAudioFile(forWriting: url, settings: format.settings)
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
      buffer.frameLength = 16_000
      for frame in 0..<16_000 {
        buffer.floatChannelData![0][frame] = frame < 8_000 ? 1 : 0
        buffer.floatChannelData![1][frame] = frame < 8_000 ? -1 : 0
      }
      try file.write(from: buffer)
    }
    let report = try AudioSignalInspector.inspect(url)
    precondition(report.channels == 2 && report.sampleRate == 16_000 && report.duration == 1)
    precondition(report.peak == 1 && report.clippedSampleFraction == 0.5 && report.quietFrameFraction == 0.5)
    precondition(abs(report.rmsDBFS - -3.0103) < 0.001)
    let candidates = try VoiceActivityTimeline.candidates(
      probabilities: [0.5] + Array(repeating: 0, count: 80) + [0.02], frameDuration: 0.256, duration: 82 * 0.256)
    precondition(candidates.ranges.count == 2)
    precondition(candidates.ranges[0].start == 0)
    let boundary = candidates.ranges[0].duration
    precondition(candidates.originalTime(for: boundary) == candidates.ranges[1].start)
    precondition(candidates.originalTime(for: boundary, isEnd: true) == boundary)
    precondition(candidates.originalTime(for: -1) == nil)
    precondition(candidates.originalTime(for: .nan) == nil)
    for probabilities: [Float] in [[], [.nan], [0], [0.1]] {
      let conservative = try VoiceActivityTimeline.candidates(probabilities: probabilities,
        frameDuration: 0.256, duration: 10)
      precondition(conservative.ranges.count == 1 && conservative.ranges[0].duration == 10)
    }
    let short = try VoiceActivityTimeline.candidates(probabilities: [0.02], frameDuration: 0.256, duration: 0.1)
    precondition(short.ranges.first?.duration == 0.1)
    let day = try SourceMediaChunk.plan(duration: 86_400)
    precondition(day.count == 96)
    for (index, chunk) in day.enumerated() {
      precondition(chunk.start == Double(index) * 900 && chunk.duration == 900)
    }
    try checkBundledModel(at: root)
    print("AudioIntelligenceChecks: PASS. Stereo PCM, conservative VAD windows, source-time mapping, 24h chunk planning, both bundle layouts, real Core ML silence inference and tamper rejection.")
  }

  private static func checkBundledModel(at root: URL) throws {
    let files = FileManager.default
    let source = URL(fileURLWithPath: files.currentDirectoryPath).appendingPathComponent("App/Resources")
    let modelName = VoiceActivityModelAssets.modelName
    let manifestName = VoiceActivityModelAssets.manifestName + ".json"
    let folder = VoiceActivityModelAssets.folderName
    for nested in [false, true] {
      let bundleURL = root.appendingPathComponent(nested ? "Nested.bundle" : "Flat.bundle")
      let resources = bundleURL.appendingPathComponent("Contents/Resources")
      let destination = nested ? resources.appendingPathComponent(folder) : resources
      try files.createDirectory(at: destination, withIntermediateDirectories: true)
      try files.copyItem(at: source.appendingPathComponent(folder).appendingPathComponent(modelName),
        to: destination.appendingPathComponent(modelName))
      try files.copyItem(at: source.appendingPathComponent(manifestName),
        to: destination.appendingPathComponent(manifestName))
      guard let bundle = Bundle(url: bundleURL),
            let modelURL = VoiceActivityModelAssets.verifiedModelURL(in: bundle) else {
        preconditionFailure("Bundled model could not be verified")
      }
      let config = MLModelConfiguration()
      config.computeUnits = .cpuOnly
      let model = try MLModel(contentsOf: modelURL, configuration: config)
      let shapes = ["audio_input": 4_160, "hidden_state": 128, "cell_state": 128]
      var input: [String: MLFeatureValue] = [:]
      for (name, count) in shapes {
        let array = try MLMultiArray(shape: [1, NSNumber(value: count)], dataType: .float32)
        for index in 0..<count { array[index] = 0 }
        input[name] = MLFeatureValue(multiArray: array)
      }
      let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: input))
      guard let value = result.featureValue(for: "vad_output")?.multiArrayValue?[0].doubleValue else {
        preconditionFailure("Bundled model did not produce a probability")
      }
      precondition((0..<0.3).contains(value))
      try Data([0]).write(to: modelURL.appendingPathComponent("model.mil"))
      precondition(VoiceActivityModelAssets.verifiedModelURL(in: bundle) == nil)
    }
  }
}
