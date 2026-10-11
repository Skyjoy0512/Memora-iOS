import Foundation

protocol SpeakerDiarizationService: Sendable {
  func analyze(_ url: URL) async throws -> SpeakerAnalysisResult
}
