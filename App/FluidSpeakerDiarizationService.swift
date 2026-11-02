@preconcurrency import CoreML
import FluidAudio
import Foundation
import AVFoundation

actor FluidSpeakerDiarizationService: SpeakerDiarizationService {
  static let shared = FluidSpeakerDiarizationService()
  private var isProcessing = false

  func analyze(_ url: URL) async throws -> SpeakerAnalysisResult {
    try await AudioProcessingDiagnostics.trace(.speakerAnalysis) { try await perform(url) } outcome: { _ in .success }
  }

  private func perform(_ url: URL) async throws -> SpeakerAnalysisResult {
    let diagnostic = AudioProcessingDiagnostics.current
    diagnostic?.setEngine(.fluidSpeaker)
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    if let diagnostic, let duration = try? await AVURLAsset(url: url).load(.duration).seconds {
      diagnostic.setAudioSeconds(duration)
    }
    let span = diagnostic?.begin(.diarization, audioSeconds: diagnostic?.snapshot.audioSeconds)
    var outcome: AudioDiagnosticReport.Outcome = .failed
    defer { diagnostic?.end(span, outcome: Task.isCancelled ? .cancelled : outcome) }
    guard !isProcessing else { throw SpeakerProcessingFailure.busy }
    isProcessing = true
    let interval = AudioProcessingDiagnostics.signposter.beginInterval("SpeakerDiarization")
    defer { AudioProcessingDiagnostics.signposter.endInterval("SpeakerDiarization", interval) }
    defer { isProcessing = false }
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
    try Task.checkCancellation()
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
    var eligibleIntervals: [String: [SpeakerInterval]] = [:]
    for chunk in result.chunkEmbeddings ?? [] {
      guard chunk.embedding256.count == 256, chunk.embedding256.allSatisfy(\.isFinite) else { continue }
      guard SpeakerEmbeddingQuality.eligible(speakerID: chunk.speakerId,
        start: chunk.startTimeSeconds, end: chunk.endTimeSeconds, intervals: intervals,
        minimumSpeechDuration: 1) else { continue }
      vectors[chunk.speakerId, default: []].append(chunk.embedding256)
      eligibleIntervals[chunk.speakerId, default: []] += intervals.filter {
        $0.speakerID == chunk.speakerId && $0.end > chunk.startTimeSeconds && $0.start < chunk.endTimeSeconds
      }.map { SpeakerInterval(speakerID: chunk.speakerId, start: max($0.start, chunk.startTimeSeconds),
        end: min($0.end, chunk.endTimeSeconds)) }
    }
    let embeddings = vectors.compactMapValues(SpeakerEmbeddingMath.mean)
    outcome = .success
    return SpeakerAnalysisResult(intervals: intervals, embeddings: embeddings,
      modelID: SpeakerModelAssets.modelID, modelVersion: SpeakerModelAssets.revision,
      eligibleSpeechDurations: eligibleIntervals.mapValues(SpeakerEmbeddingQuality.duration))
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
