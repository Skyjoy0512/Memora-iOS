@preconcurrency import CoreML
import FluidAudio
import Foundation

actor FluidSpeakerDiarizationService: SpeakerDiarizationService {
  static let shared = FluidSpeakerDiarizationService()
  private var isProcessing = false

  func analyze(_ url: URL) async throws -> SpeakerAnalysisResult {
    guard !isProcessing else { throw SpeakerProcessingFailure.busy }
    isProcessing = true
    defer { isProcessing = false }
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    let directory = try await SpeakerModelAssets.shared.verifiedDirectory()
    try Task.checkCancellation()
    let configuration = MLModelConfiguration()
    configuration.computeUnits = .all
    let cpuConfiguration = MLModelConfiguration()
    cpuConfiguration.computeUnits = .cpuOnly
    let models = try OfflineDiarizerModels(
      segmentationModel: MLModel(contentsOf: directory.appendingPathComponent("Segmentation.mlmodelc"), configuration: configuration),
      fbankModel: MLModel(contentsOf: directory.appendingPathComponent("FBank.mlmodelc"), configuration: cpuConfiguration),
      embeddingModel: MLModel(contentsOf: directory.appendingPathComponent("Embedding.mlmodelc"), configuration: configuration),
      pldaRhoModel: MLModel(contentsOf: directory.appendingPathComponent("PldaRho.mlmodelc"), configuration: configuration),
      pldaPsi: loadPsi(directory), compilationDuration: 0
    )
    var config = OfflineDiarizerConfig.default
    config.exposeChunkEmbeddings = true
    let manager = OfflineDiarizerManager(config: config)
    manager.initialize(models: models)
    let result: DiarizationResult
    do {
      result = try await manager.process(url)
    } catch OfflineDiarizationError.noSpeechDetected {
      throw SpeakerProcessingFailure.noSpeech
    }
    try Task.checkCancellation()
    let intervals = result.segments.map {
      SpeakerInterval(speakerID: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds))
    }.filter(\.isValid)
    guard !intervals.isEmpty else { throw SpeakerProcessingFailure.noSpeech }
    var vectors: [String: [[Float]]] = [:]
    for chunk in result.chunkEmbeddings ?? [] {
      guard chunk.embedding256.count == 256, chunk.embedding256.allSatisfy(\.isFinite) else { continue }
      vectors[chunk.speakerId, default: []].append(chunk.embedding256)
    }
    let embeddings = vectors.compactMapValues(SpeakerEmbeddingMath.mean)
    return SpeakerAnalysisResult(intervals: intervals, embeddings: embeddings,
      modelID: SpeakerModelAssets.modelID, modelVersion: SpeakerModelAssets.revision)
  }

  private func loadPsi(_ directory: URL) throws -> [Double] {
    let data = try Data(contentsOf: directory.appendingPathComponent("plda-parameters.json"))
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let tensors = root["tensors"] as? [String: Any], let psi = tensors["psi"] as? [String: Any],
          psi["dtype"] as? String == "float32", let base64 = psi["data_base64"] as? String,
          let decoded = Data(base64Encoded: base64), decoded.count == 128 * 4 else {
      throw SpeakerProcessingFailure.assetsInvalid
    }
    var floats = [Float](repeating: 0, count: 128)
    _ = floats.withUnsafeMutableBytes { decoded.copyBytes(to: $0) }
    guard floats.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw SpeakerProcessingFailure.assetsInvalid }
    return floats.map(Double.init)
  }
}
