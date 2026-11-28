import CoreML
import Foundation

/// Verifies the bundled voice activity model and compares the compute units it
/// can run on: load time, per-prediction time, and the numeric result of each.
@main
enum VoiceActivityModelChecks {
  static func main() throws {
    setvbuf(stdout, nil, _IONBF, 0)
    setvbuf(stderr, nil, _IONBF, 0)
    // Mirror the shipped bundle: the compiled model as a package, with the
    // manifest's files also flattened beside it, which is what Bitrig produces.
    let source = URL(fileURLWithPath: "App/Resources/VoiceActivity", isDirectory: true)
    let manifest = URL(fileURLWithPath: "App/Resources/VoiceActivityModelManifest.json")
    let bundleRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("vad-bundle-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: bundleRoot) }
    try FileManager.default.copyItem(
      at: source.appendingPathComponent(VoiceActivityModelAssets.modelName),
      to: bundleRoot.appendingPathComponent(VoiceActivityModelAssets.modelName))
    let assets = try JSONDecoder().decode([ManifestAsset].self, from: Data(contentsOf: manifest))
    for asset in assets {
      let destination = bundleRoot.appendingPathComponent(asset.path)
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.copyItem(
        at: source.appendingPathComponent(VoiceActivityModelAssets.modelName)
          .appendingPathComponent(asset.path), to: destination)
    }
    guard let url = VoiceActivityModelAssets.verifiedModelURL(
      root: bundleRoot, fallbackRoot: nil, manifestURL: manifest) else {
      preconditionFailure("The bundled model does not match its manifest")
    }
    precondition(url.lastPathComponent == VoiceActivityModelAssets.modelName)

    // A tampered file must be refused, so an unverified model can never run.
    let tampered = FileManager.default.temporaryDirectory
      .appendingPathComponent("vad-tampered-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tampered, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tampered) }
    try FileManager.default.copyItem(
      at: bundleRoot.appendingPathComponent(VoiceActivityModelAssets.modelName),
      to: tampered.appendingPathComponent(VoiceActivityModelAssets.modelName))
    for asset in assets.dropFirst() {
      let destination = tampered.appendingPathComponent(asset.path)
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.copyItem(
        at: bundleRoot.appendingPathComponent(asset.path), to: destination)
    }
    precondition(VoiceActivityModelAssets.verifiedModelURL(root: tampered, fallbackRoot: nil,
                                                          manifestURL: manifest) == nil,
                 "A bundle missing an asset must not verify")
    print("Voice activity: manifest verification and refusal of a missing bundle passed.")

    let cases: [(String, MLComputeUnits)] = [
      ("all", .all),
      ("cpuAndNeuralEngine", .cpuAndNeuralEngine),
      ("cpuAndGPU", .cpuAndGPU),
      ("cpuOnly", .cpuOnly),
    ]
    var reference: [Float]?
    var loads: [String: [Double]] = [:]
    var predictions: [String: [Double]] = [:]
    // Round-robin, so a later placement is not compared against a cold first one.
    for _ in 0..<3 {
      for (name, units) in cases {
        let configuration = VoiceActivityModelAssets.configuration(computeUnits: units)
        let loadStart = ContinuousClock.now
        let model = try MLModel(contentsOf: url, configuration: configuration)
        let loadEnd = ContinuousClock.now
        let measured = try predict(model, trials: 40)
        loads[name, default: []].append(milliseconds(loadStart, loadEnd))
        predictions[name, default: []].append(measured.medianMS)
        let output = measured.output
        if let reference {
          for (index, value) in zip(reference, output).enumerated() where abs(value.1 - value.0) > 1e-3 {
            print("compute units \(name) differ at \(index): \(value.0) vs \(value.1)")
          }
        } else {
          reference = output
        }
      }
    }
    for (name, _) in cases {
      let load = loads[name]!.sorted()[1]
      let prediction = predictions[name]!.sorted()[1]
      print("{\"computeUnits\":\"\(name)\",\"loadMS\":\(round(load * 1000) / 1000),\"predictionMedianMS\":\(round(prediction * 1000) / 1000)}")
    }
  }

  /// Runs the model with a fixed input so the placements can be compared and
  /// their answer checked against each other.
  private static func predict(_ model: MLModel, trials: Int) throws -> (output: [Float], medianMS: Double) {
    let audio = try MLMultiArray(shape: [1, 4_160], dataType: .float32)
    let cell = try MLMultiArray(shape: [1, 128], dataType: .float32)
    let hidden = try MLMultiArray(shape: [1, 128], dataType: .float32)
    for index in 0..<4_160 {
      audio[index] = NSNumber(value: Float(sin(Double(index) * 0.05)) * 0.2)
    }
    for index in 0..<128 {
      cell[index] = 0
      hidden[index] = 0
    }
    let provider = try MLDictionaryFeatureProvider(dictionary: [
      "audio_input": audio, "cell_state": cell, "hidden_state": hidden,
    ])
    var times: [Double] = []
    var last: [Float] = []
    for _ in 0..<trials {
      let start = ContinuousClock.now
      let result = try model.prediction(from: provider)
      let end = ContinuousClock.now
      times.append(milliseconds(start, end))
      guard let output = result.featureValue(for: "vad_output")?.multiArrayValue else {
        preconditionFailure("The model returned no voice activity output")
      }
      last = [output[0].floatValue]
    }
    times.sort()
    return (last, times[times.count / 2])
  }

  private static func milliseconds(_ start: ContinuousClock.Instant, _ end: ContinuousClock.Instant) -> Double {
    let time = start.duration(to: end).components
    return Double(time.seconds) * 1_000 + Double(time.attoseconds) / 1e15
  }
}


private struct ManifestAsset: Decodable {
  var path: String
  var size: Int
  var hash: String
  var isSHA256: Bool
}
