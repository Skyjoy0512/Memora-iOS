import Foundation

@main
struct SpeakerProcessingChecks {
  static func main() throws {
    precondition(SpeakerEmbeddingMath.cosine([1, 0], [1, 0]) == 1)
    precondition(SpeakerEmbeddingMath.cosine([1, 0], [0, 1]) == 0)
    precondition(SpeakerEmbeddingMath.cosine([1], [-1]) == -1)
    precondition(SpeakerEmbeddingMath.cosine([0, 0], [1, 0]) == nil)
    precondition(SpeakerEmbeddingMath.cosine([1], [1, 2]) == nil)
    precondition(SpeakerEmbeddingMath.cosine([.nan], [1]) == nil)
    precondition(SpeakerEmbeddingMath.mean([[1, 0], [1, 0]]) == [1, 0])
    precondition(SpeakerEmbeddingMath.mean([[1], [1, 2]]) == nil)
    precondition(SpeakerEmbeddingMath.mean([]) == nil)

    let original = TranscriptSegment(id: UUID(), speaker: "話者", speakerIsCertain: false,
      timestamp: 2, text: "発言の原文", endTime: 5)
    let intervals = [SpeakerInterval(speakerID: "S1", start: 1, end: 6)]
    let matched = SpeakerTranscriptAligner.align([original], intervals: intervals, minimumDuration: 1)[0]
    precondition(matched.speakerID == "S1" && matched.identificationStatus == .anonymous)
    precondition(!matched.speakerIsCertain && matched.text == original.text && matched.timestamp == original.timestamp)
    let overlapping = intervals + [SpeakerInterval(speakerID: "S2", start: 3, end: 4)]
    let ambiguous = SpeakerTranscriptAligner.align([original], intervals: overlapping, minimumDuration: 1)[0]
    precondition(ambiguous.identificationStatus == .overlap && ambiguous.speakerID == nil)
    let transition = [SpeakerInterval(speakerID: "S1", start: 1, end: 3), SpeakerInterval(speakerID: "S2", start: 3, end: 6)]
    precondition(SpeakerTranscriptAligner.align([original], intervals: transition, minimumDuration: 1)[0].speakerID == nil)
    let gap = [SpeakerInterval(speakerID: "S1", start: 2, end: 3)]
    precondition(SpeakerTranscriptAligner.align([original], intervals: gap, minimumDuration: 1)[0].speakerID == nil)
    var noTiming = original
    noTiming.endTime = nil
    precondition(SpeakerTranscriptAligner.align([noTiming], intervals: intervals, minimumDuration: 1)[0].identificationStatus == .insufficientTiming)
    var short = original
    short.endTime = 2.2
    precondition(SpeakerTranscriptAligner.align([short], intervals: intervals, minimumDuration: 1)[0].speakerID == nil)
    var manual = original
    manual.speaker = "自分"
    manual.identificationStatus = .manual
    precondition(SpeakerTranscriptAligner.align([manual], intervals: overlapping, minimumDuration: 1)[0] == manual)
    let data = try JSONEncoder().encode(matched)
    let decodedSegment = try JSONDecoder().decode(TranscriptSegment.self, from: data)
    precondition(decodedSegment == matched)
    var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    for key in ["endTime", "speakerID", "identificationStatus"] { legacy.removeValue(forKey: key) }
    let old = try JSONDecoder().decode(TranscriptSegment.self, from: JSONSerialization.data(withJSONObject: legacy))
    precondition(old.endTime == nil && old.speakerID == nil && old.identificationStatus == .unassigned)
    legacy["speaker"] = "田中"
    legacy["speakerIsCertain"] = true
    var oldNamed = try JSONDecoder().decode(TranscriptSegment.self, from: JSONSerialization.data(withJSONObject: legacy))
    oldNamed.endTime = 5
    precondition(oldNamed.identificationStatus == .manual)
    precondition(SpeakerTranscriptAligner.align([oldNamed], intervals: overlapping, minimumDuration: 1)[0] == oldNamed)
    let vector = [Float](repeating: 1 / 16, count: 256)
    let profile = SpeakerProfile(embeddingData: vector, embeddingModelID: "test256",
      embeddingModelVersion: "v1", embeddingDimension: 256, enrollmentDuration: 20, consentAt: .now,
      qualityMetadata: VoiceQualityMetadata(sampleDuration: 20, speechDuration: 15, peak: 0.5,
        rootMeanSquare: 0.1, clippedSampleCount: 0, detectedSpeakerCount: 1))
    let result = SpeakerAnalysisResult(intervals: intervals, embeddings: ["S1": vector], modelID: "test256", modelVersion: "v1")
    let similarities = try SpeakerIdentificationService.similarities(profile: profile, result: result)
    precondition(similarities["S1"] == 1)
    var disabled = profile
    disabled.isEnabled = false
    let disabledSimilarities = try SpeakerIdentificationService.similarities(profile: disabled, result: result)
    precondition(disabledSimilarities.isEmpty)
    var mismatched = result
    mismatched.modelVersion = "v2"
    do {
      _ = try SpeakerIdentificationService.similarities(profile: profile, result: mismatched)
      preconditionFailure("incompatible model accepted")
    } catch SpeakerProcessingFailure.modelMismatch { }
    let encoded = try JSONEncoder().encode(profile)
    let decodedProfile = try JSONDecoder().decode(SpeakerProfile.self, from: encoded)
    precondition(decodedProfile == profile)
    print("SpeakerProcessingChecks: passed (math, compatibility, interval ambiguity, manual edits, legacy codec)")
  }
}
