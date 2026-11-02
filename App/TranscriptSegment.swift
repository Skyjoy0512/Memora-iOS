import Foundation

struct TranscriptSegment: Identifiable, Hashable, Codable {
  var id: UUID
  var speaker: String
  var speakerIsCertain: Bool
  var timestamp: TimeInterval
  var text: String
  var endTime: TimeInterval? = nil
  var speakerID: String? = nil
  var identificationStatus: SpeakerIdentificationStatus = .unassigned
  var recognitionEngine: String? = nil
  var recognitionModel: String? = nil
  var recognitionLanguage: String? = nil
  var recognitionConfidence: Double? = nil

  private enum CodingKeys: String, CodingKey {
    case id, speaker, speakerIsCertain, timestamp, text, endTime, speakerID, identificationStatus
    case recognitionEngine, recognitionModel, recognitionLanguage, recognitionConfidence
  }

  init(id: UUID, speaker: String, speakerIsCertain: Bool, timestamp: TimeInterval, text: String,
       endTime: TimeInterval? = nil, speakerID: String? = nil,
       identificationStatus: SpeakerIdentificationStatus? = nil,
       recognitionEngine: String? = nil, recognitionModel: String? = nil,
       recognitionLanguage: String? = nil, recognitionConfidence: Double? = nil) {
    self.id = id
    self.speaker = speaker
    self.speakerIsCertain = speakerIsCertain
    self.timestamp = timestamp
    self.text = text
    self.endTime = endTime
    self.speakerID = speakerID
    self.identificationStatus = identificationStatus ?? (speakerIsCertain ? .manual : .unassigned)
    self.recognitionEngine = recognitionEngine
    self.recognitionModel = recognitionModel
    self.recognitionLanguage = recognitionLanguage
    self.recognitionConfidence = recognitionConfidence
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    speaker = try container.decode(String.self, forKey: .speaker)
    speakerIsCertain = try container.decode(Bool.self, forKey: .speakerIsCertain)
    timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
    text = try container.decode(String.self, forKey: .text)
    endTime = try container.decodeIfPresent(TimeInterval.self, forKey: .endTime)
    speakerID = try container.decodeIfPresent(String.self, forKey: .speakerID)
    identificationStatus = try container.decodeIfPresent(SpeakerIdentificationStatus.self, forKey: .identificationStatus)
      ?? (speakerIsCertain ? .manual : .unassigned)
    recognitionEngine = try container.decodeIfPresent(String.self, forKey: .recognitionEngine)
    recognitionModel = try container.decodeIfPresent(String.self, forKey: .recognitionModel)
    recognitionLanguage = try container.decodeIfPresent(String.self, forKey: .recognitionLanguage)
    recognitionConfidence = try container.decodeIfPresent(Double.self, forKey: .recognitionConfidence)
  }
}
