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
    precondition(decodedProfile.sampleCount == 1 && decodedProfile.isValid)
    let combined = try VoiceEnrollmentBuilder.profile(results: [result, result],
      qualities: [profile.qualityMetadata, profile.qualityMetadata], consentAt: profile.consentAt)
    precondition(combined.sampleCount == 2 && combined.enrollmentDuration == 40)
    precondition(combined.qualityMetadata.speechDuration == 30 && combined.qualityMetadata.peak == 0.5)
    precondition(abs(combined.qualityMetadata.rootMeanSquare - 0.1) < 0.000001)
    precondition(SpeakerEmbeddingMath.cosine(combined.embeddingData, vector) == 1)
    var firstAxis = [Float](repeating: 0, count: 256)
    firstAxis[0] = 2
    var secondAxis = [Float](repeating: 0, count: 256)
    secondAxis[1] = 20
    var firstResult = result
    firstResult.embeddings = ["S1": firstAxis]
    var secondResult = result
    secondResult.embeddings = ["S9": secondAxis]
    let equalSamples = try VoiceEnrollmentBuilder.profile(results: [firstResult, secondResult],
      qualities: [profile.qualityMetadata, profile.qualityMetadata], consentAt: .now)
    precondition(abs(equalSamples.embeddingData[0] - equalSamples.embeddingData[1]) < 0.000001)
    precondition(abs(equalSamples.embeddingData[0] - Float(1 / sqrt(2.0))) < 0.000001)
    let combinedData = try JSONEncoder().encode(combined)
    let combinedRestored = try JSONDecoder().decode(SpeakerProfile.self, from: combinedData)
    precondition(combinedRestored == combined && combinedRestored.sampleCount == 2)
    var oldProfileJSON = try JSONSerialization.jsonObject(with: combinedData) as! [String: Any]
    oldProfileJSON.removeValue(forKey: "enrollmentSamples")
    let oldProfile = try JSONDecoder().decode(SpeakerProfile.self,
      from: JSONSerialization.data(withJSONObject: oldProfileJSON))
    precondition(oldProfile.sampleCount == 1 && oldProfile.isValid)
    do {
      _ = try VoiceEnrollmentBuilder.profile(results: [result, mismatched],
        qualities: [profile.qualityMetadata, profile.qualityMetadata], consentAt: .now)
      preconditionFailure("different sample models combined")
    } catch SpeakerProcessingFailure.modelMismatch { }
    do {
      _ = try VoiceEnrollmentBuilder.profile(results: [result], qualities: [], consentAt: .now)
      preconditionFailure("missing quality accepted")
    } catch SpeakerProcessingFailure.invalidEmbedding { }
    var invalidResult = result
    invalidResult.embeddings = ["S1": vector, "S2": vector]
    do {
      _ = try VoiceEnrollmentBuilder.profile(results: [invalidResult], qualities: [profile.qualityMetadata], consentAt: .now)
      preconditionFailure("multiple speaker embeddings accepted for enrollment")
    } catch SpeakerProcessingFailure.invalidEmbedding { }
    do {
      _ = try VoiceEnrollmentBuilder.profile(results: [result, result, result, result],
        qualities: Array(repeating: profile.qualityMetadata, count: 4), consentAt: .now)
      preconditionFailure("unbounded enrollment accepted")
    } catch SpeakerProcessingFailure.invalidEmbedding { }
    var invalidQuality = profile.qualityMetadata
    invalidQuality.speechDuration = .nan
    precondition(!invalidQuality.isValid)
    invalidQuality = profile.qualityMetadata
    invalidQuality.speechDuration = 21
    precondition(!invalidQuality.isValid)
    invalidQuality = profile.qualityMetadata
    invalidQuality.clippedSampleCount = 1
    precondition(!invalidQuality.isValid)
    invalidQuality = profile.qualityMetadata
    invalidQuality.detectedSpeakerCount = 2
    do {
      _ = try VoiceEnrollmentBuilder.profile(results: [result], qualities: [invalidQuality], consentAt: .now)
      preconditionFailure("invalid quality accepted")
    } catch SpeakerProcessingFailure.invalidEmbedding { }
    var invalidProfile = profile
    invalidProfile.isCurrentUser = false
    precondition(!invalidProfile.isValid)
    invalidProfile = profile
    invalidProfile.enrollmentSamples = []
    precondition(!invalidProfile.isValid)

    var matchAxis = [Float](repeating: 0, count: 256)
    matchAxis[0] = 1
    let matchProfile = SpeakerProfile(embeddingData: matchAxis, embeddingModelID: "match256",
      embeddingModelVersion: "v1", embeddingDimension: 256, enrollmentDuration: 20, consentAt: .now,
      qualityMetadata: profile.qualityMetadata)
    func matchVector(_ similarity: Double) -> [Float] {
      var vector = [Float](repeating: 0, count: 256)
      let angle = acos(max(-1, min(1, similarity)))
      vector[0] = Float(cos(angle))
      vector[1] = Float(sin(angle))
      return vector
    }
    func match(_ result: SpeakerAnalysisResult, similarity: Double = 0.8,
               lead: Double = 0.1, speech: Double = 1.5) throws -> SpeakerIdentificationService.SelfMatch? {
      try SpeakerIdentificationService.selfMatch(profile: matchProfile, result: result,
        minimumSimilarity: similarity, minimumLead: lead, minimumEligibleSpeech: speech)
    }
    func requireNoMatch(_ result: SpeakerAnalysisResult, similarity: Double = 0.8,
                        lead: Double = 0.1, speech: Double = 1.5) throws {
      let matched = try match(result, similarity: similarity, lead: lead, speech: speech)
      precondition(matched == nil, "unexpected self-match")
    }
    func requireSendable<T: Sendable>(_ value: T) -> T { value }

    let successMatchResult = SpeakerAnalysisResult(
      intervals: [SpeakerInterval(speakerID: "S1", start: 0, end: 3),
                  SpeakerInterval(speakerID: "S2", start: 3, end: 5)],
      embeddings: ["S1": matchVector(0.9), "S2": matchVector(0.55)],
      modelID: "match256", modelVersion: "v1",
      eligibleSpeechDurations: ["S1": 2.5, "S2": 1.8])
    if let matchedSelf = try match(successMatchResult) {
      precondition(matchedSelf.speakerID == "S1")
      precondition(abs(matchedSelf.similarity - 0.9) < 0.0001)
      precondition(matchedSelf == SpeakerIdentificationService.SelfMatch(speakerID: "S1",
        similarity: matchedSelf.similarity))
      _ = requireSendable(matchedSelf)
    } else {
      preconditionFailure("valid top candidate was not matched")
    }

    var missingWinnerDuration = successMatchResult
    missingWinnerDuration.eligibleSpeechDurations = ["S2": 1.8]
    try requireNoMatch(missingWinnerDuration)

    var shortWinnerDuration = successMatchResult
    shortWinnerDuration.eligibleSpeechDurations = ["S1": 0.5, "S2": 1.8]
    try requireNoMatch(shortWinnerDuration)

    var belowThreshold = successMatchResult
    belowThreshold.embeddings = ["S1": matchVector(0.7), "S2": matchVector(0.4)]
    try requireNoMatch(belowThreshold)

    var durationCannotWin = successMatchResult
    durationCannotWin.embeddings = ["S1": matchVector(0.6), "S2": matchVector(0.9)]
    durationCannotWin.eligibleSpeechDurations = ["S1": 100, "S2": 0.2]
    try requireNoMatch(durationCannotWin, similarity: 0.5, lead: 0.1, speech: 1)

    var tiedWinner = successMatchResult
    tiedWinner.embeddings = ["S1": matchVector(0.9), "S2": matchVector(0.9)]
    tiedWinner.eligibleSpeechDurations = ["S1": 2.5, "S2": 2.5]
    try requireNoMatch(tiedWinner)

    var nearTieMissingRivalDuration = successMatchResult
    nearTieMissingRivalDuration.embeddings = ["S1": matchVector(0.9), "S2": matchVector(0.87)]
    nearTieMissingRivalDuration.eligibleSpeechDurations = ["S1": 2.5]
    try requireNoMatch(nearTieMissingRivalDuration, similarity: 0.8, lead: 0.05, speech: 1.5)

    var nearTieShortRivalDuration = nearTieMissingRivalDuration
    nearTieShortRivalDuration.eligibleSpeechDurations = ["S1": 2.5, "S2": 0.2]
    try requireNoMatch(nearTieShortRivalDuration, similarity: 0.8, lead: 0.05, speech: 1.5)

    var nearTieBelowThresholdRival = successMatchResult
    nearTieBelowThresholdRival.embeddings = ["S1": matchVector(0.82), "S2": matchVector(0.8)]
    nearTieBelowThresholdRival.eligibleSpeechDurations = ["S1": 2.5, "S2": 0.2]
    try requireNoMatch(nearTieBelowThresholdRival, similarity: 0.81, lead: 0.05, speech: 1.5)

    var separatedWinner = successMatchResult
    separatedWinner.embeddings = ["S1": matchVector(0.9), "S2": matchVector(0.84)]
    separatedWinner.eligibleSpeechDurations = ["S1": 2.5, "S2": 0.2]
    let separatedMatch = try match(separatedWinner, similarity: 0.8, lead: 0.05, speech: 1.5)
    precondition(separatedMatch?.speakerID == "S1")

    let evidenceRecordID = UUID()
    let evidenceFingerprint = "aligned-transcript-fingerprint"
    let evidence = SpeakerTaskOwnershipEvidence(recordID: evidenceRecordID, speakerID: "S1",
      profileID: matchProfile.id, profileUpdatedAt: matchProfile.updatedAt,
      transcriptFingerprint: evidenceFingerprint, similarity: 0.93)
    func matchesEvidence(_ candidate: SpeakerTaskOwnershipEvidence, recordID: UUID,
                         profile: SpeakerProfile, fingerprint: String,
                         minimumSimilarity: Double) -> Bool {
      candidate.matches(recordID: recordID, profile: profile,
        transcriptFingerprint: fingerprint, minimumSimilarity: minimumSimilarity)
    }
    func requireEvidenceMatch(_ candidate: SpeakerTaskOwnershipEvidence, recordID: UUID,
                              profile: SpeakerProfile, fingerprint: String,
                              minimumSimilarity: Double) {
      precondition(matchesEvidence(candidate, recordID: recordID, profile: profile,
        fingerprint: fingerprint, minimumSimilarity: minimumSimilarity), "valid evidence rejected")
    }
    func requireEvidenceRejection(_ candidate: SpeakerTaskOwnershipEvidence, recordID: UUID,
                                  profile: SpeakerProfile, fingerprint: String,
                                  minimumSimilarity: Double) {
      precondition(!matchesEvidence(candidate, recordID: recordID, profile: profile,
        fingerprint: fingerprint, minimumSimilarity: minimumSimilarity), "invalid evidence accepted")
    }

    requireEvidenceMatch(evidence, recordID: evidenceRecordID, profile: matchProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 0.92)
    _ = requireSendable(evidence)
    let evidenceData = try JSONEncoder().encode(evidence)
    let decodedEvidence = try JSONDecoder().decode(SpeakerTaskOwnershipEvidence.self, from: evidenceData)
    precondition(decodedEvidence == evidence)

    var tamperedRecord = evidence
    tamperedRecord.recordID = UUID()
    requireEvidenceRejection(tamperedRecord, recordID: evidenceRecordID, profile: matchProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 0.92)
    requireEvidenceRejection(evidence, recordID: UUID(), profile: matchProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 0.92)

    var emptySpeaker = evidence
    emptySpeaker.speakerID = ""
    requireEvidenceRejection(emptySpeaker, recordID: evidenceRecordID, profile: matchProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 0.92)
    var blankSpeaker = evidence
    blankSpeaker.speakerID = "   "
    requireEvidenceRejection(blankSpeaker, recordID: evidenceRecordID, profile: matchProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 0.92)

    var changedProfile = evidence
    changedProfile.profileID = UUID()
    requireEvidenceRejection(changedProfile, recordID: evidenceRecordID, profile: matchProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 0.92)
    var otherProfile = matchProfile
    otherProfile.id = UUID()
    requireEvidenceRejection(evidence, recordID: evidenceRecordID, profile: otherProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 0.92)

    var changedRevision = evidence
    changedRevision.profileUpdatedAt = matchProfile.updatedAt.addingTimeInterval(1)
    requireEvidenceRejection(changedRevision, recordID: evidenceRecordID, profile: matchProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 0.92)
    var newerProfile = matchProfile
    newerProfile.updatedAt = matchProfile.updatedAt.addingTimeInterval(1)
    requireEvidenceRejection(evidence, recordID: evidenceRecordID, profile: newerProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 0.92)

    var changedTranscript = evidence
    changedTranscript.transcriptFingerprint = "changed-fingerprint"
    requireEvidenceRejection(changedTranscript, recordID: evidenceRecordID, profile: matchProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 0.92)
    requireEvidenceRejection(evidence, recordID: evidenceRecordID, profile: matchProfile,
      fingerprint: "changed-fingerprint", minimumSimilarity: 0.92)
    requireEvidenceRejection(evidence, recordID: evidenceRecordID, profile: matchProfile,
      fingerprint: "", minimumSimilarity: 0.92)

    var disabledEvidenceProfile = matchProfile
    disabledEvidenceProfile.isEnabled = false
    requireEvidenceRejection(evidence, recordID: evidenceRecordID, profile: disabledEvidenceProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 0.92)

    var invalidEvidenceProfile = matchProfile
    invalidEvidenceProfile.isCurrentUser = false
    requireEvidenceRejection(evidence, recordID: evidenceRecordID, profile: invalidEvidenceProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 0.92)

    for malformedSimilarity in [Double.nan, .infinity, -Double.infinity, -0.01, 1.01] {
      var malformedEvidence = evidence
      malformedEvidence.similarity = malformedSimilarity
      requireEvidenceRejection(malformedEvidence, recordID: evidenceRecordID, profile: matchProfile,
        fingerprint: evidenceFingerprint, minimumSimilarity: 0.92)
    }
    for invalidThreshold in [Double.nan, .infinity, -Double.infinity, -0.01, 1.01] {
      requireEvidenceRejection(evidence, recordID: evidenceRecordID, profile: matchProfile,
        fingerprint: evidenceFingerprint, minimumSimilarity: invalidThreshold)
    }
    requireEvidenceRejection(evidence, recordID: evidenceRecordID, profile: matchProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 0.95)

    var blankStoredFingerprint = evidence
    blankStoredFingerprint.transcriptFingerprint = "   "
    requireEvidenceRejection(blankStoredFingerprint, recordID: evidenceRecordID, profile: matchProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 0.92)
    requireEvidenceRejection(evidence, recordID: evidenceRecordID, profile: matchProfile,
      fingerprint: "   ", minimumSimilarity: 0.92)

    var boundaryEvidence = evidence
    boundaryEvidence.similarity = 0.92
    requireEvidenceMatch(boundaryEvidence, recordID: evidenceRecordID, profile: matchProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 0.92)

    var fullSimilarityEvidence = evidence
    fullSimilarityEvidence.similarity = 1
    requireEvidenceMatch(fullSimilarityEvidence, recordID: evidenceRecordID, profile: matchProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 1)
    var zeroSimilarityEvidence = evidence
    zeroSimilarityEvidence.similarity = 0
    requireEvidenceMatch(zeroSimilarityEvidence, recordID: evidenceRecordID, profile: matchProfile,
      fingerprint: evidenceFingerprint, minimumSimilarity: 0)

    var disabledMatchProfile = matchProfile
    disabledMatchProfile.isEnabled = false
    let disabledMatch = try SpeakerIdentificationService.selfMatch(profile: disabledMatchProfile,
      result: successMatchResult, minimumSimilarity: 0.8, minimumLead: 0.1,
      minimumEligibleSpeech: 1.5)
    precondition(disabledMatch == nil)

    var invalidMatchProfile = matchProfile
    invalidMatchProfile.isCurrentUser = false
    do {
      _ = try SpeakerIdentificationService.selfMatch(profile: invalidMatchProfile, result: successMatchResult,
        minimumSimilarity: 0.8, minimumLead: 0.1, minimumEligibleSpeech: 1.5)
      preconditionFailure("invalid match profile accepted")
    } catch SpeakerProcessingFailure.invalidEmbedding { }

    var mismatchedMatchResult = successMatchResult
    mismatchedMatchResult.modelVersion = "v2"
    do {
      _ = try match(mismatchedMatchResult)
      preconditionFailure("incompatible match model accepted")
    } catch SpeakerProcessingFailure.modelMismatch { }

    var emptyMatchResult = successMatchResult
    emptyMatchResult.embeddings = [:]
    try requireNoMatch(emptyMatchResult)
    var malformedMatchResult = successMatchResult
    malformedMatchResult.embeddings = ["S1": [1, 0]]
    try requireNoMatch(malformedMatchResult)
    var mixedMalformedMatchResult = successMatchResult
    mixedMalformedMatchResult.embeddings["S2"] = [1, 0]
    try requireNoMatch(mixedMalformedMatchResult)
    var emptyKeyMatchResult = successMatchResult
    emptyKeyMatchResult.embeddings[""] = matchVector(0.5)
    try requireNoMatch(emptyKeyMatchResult)
    var nonFiniteMatchResult = successMatchResult
    nonFiniteMatchResult.embeddings["S2"] = [Float.nan] + [Float](repeating: 0, count: 255)
    try requireNoMatch(nonFiniteMatchResult)

    var missingWinnerInterval = successMatchResult
    missingWinnerInterval.intervals = [SpeakerInterval(speakerID: "S2", start: 0, end: 3)]
    try requireNoMatch(missingWinnerInterval)
    var invalidWinnerInterval = successMatchResult
    invalidWinnerInterval.intervals = [SpeakerInterval(speakerID: "S1", start: 3, end: 3)]
    try requireNoMatch(invalidWinnerInterval)

    func expectInvalidMatchLimits(_ similarity: Double, _ lead: Double, _ speech: Double) {
      do {
        _ = try SpeakerIdentificationService.selfMatch(profile: matchProfile, result: successMatchResult,
          minimumSimilarity: similarity, minimumLead: lead, minimumEligibleSpeech: speech)
        preconditionFailure("invalid self-match limits accepted")
      } catch SpeakerProcessingFailure.invalidEmbedding {
      } catch {
        preconditionFailure("unexpected self-match limit failure")
      }
    }
    expectInvalidMatchLimits(0, 0.1, 1.5)
    expectInvalidMatchLimits(1.01, 0.1, 1.5)
    expectInvalidMatchLimits(.nan, 0.1, 1.5)
    expectInvalidMatchLimits(.infinity, 0.1, 1.5)
    expectInvalidMatchLimits(0.8, 0, 1.5)
    expectInvalidMatchLimits(0.8, 1.01, 1.5)
    expectInvalidMatchLimits(0.8, .nan, 1.5)
    expectInvalidMatchLimits(0.8, .infinity, 1.5)
    expectInvalidMatchLimits(0.8, 0.1, 0)
    expectInvalidMatchLimits(0.8, 0.1, -1)
    expectInvalidMatchLimits(0.8, 0.1, .nan)
    expectInvalidMatchLimits(0.8, 0.1, .infinity)
    let boundaryMatch = try match(successMatchResult, similarity: 1, lead: 1, speech: 2.5)
    precondition(boundaryMatch == nil)

    // An action is tied to a speaker only when its wording clearly matches one.
    let quoteSegment = TranscriptSegment(id: UUID(), speaker: "話者A", speakerIsCertain: false,
      timestamp: 1, text: "見積書は金曜までに送ります", endTime: 4, speakerID: "S1",
      identificationStatus: .anonymous)
    let planSegment = TranscriptSegment(id: UUID(), speaker: "話者B", speakerIsCertain: false,
      timestamp: 6, text: "資料は来週共有します", endTime: 9, speakerID: "S2",
      identificationStatus: .anonymous)
    let quoted = [quoteSegment, planSegment]
    precondition(ActionSpeakerMatch.speakerID(forAction: "見積書を金曜までに送付", in: quoted) == "S1")
    precondition(ActionSpeakerMatch.speakerID(forAction: "資料を来週共有する", in: quoted) == "S2")
    precondition(ActionSpeakerMatch.speakerID(forAction: "予算の確認をお願いします", in: quoted) == nil)
    precondition(ActionSpeakerMatch.speakerID(forAction: "見積書", in: quoted) == nil)
    let duplicateSegments = [quoteSegment, TranscriptSegment(id: UUID(), speaker: "話者C",
      speakerIsCertain: false, timestamp: 10, text: "見積書は金曜までに送ります", endTime: 13,
      speakerID: "S3", identificationStatus: .anonymous)]
    precondition(ActionSpeakerMatch.speakerID(forAction: "見積書を金曜までに送付", in: duplicateSegments) == nil)
    let unnamedSegment = TranscriptSegment(id: UUID(), speaker: "話者A", speakerIsCertain: false,
      timestamp: 1, text: "見積書は金曜までに送ります", endTime: 4)
    precondition(ActionSpeakerMatch.speakerID(forAction: "見積書を金曜までに送付", in: [unnamedSegment]) == nil)

    precondition(matchProfile.embeddingData == matchAxis)
    precondition(successMatchResult.embeddings["S1"] == matchVector(0.9))
    print("SpeakerProcessingChecks: passed (math, compatibility, intervals, manual edits, legacy codec, multi-sample enrollment, self-match, task-ownership evidence, action wording)")
  }
}
