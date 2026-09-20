import Foundation

struct Meeting: Identifiable, Hashable, Codable {
  var id: UUID
  var title: String
  var createdAt: Date
  var duration: TimeInterval
  var source: MeetingSource
  var status: MeetingStatus
  var summary: String
  var keyPoints: [String]
  var decisions: [String]
  var openQuestions: [String]
  var transcript: [TranscriptSegment]
  var spaceID: UUID?
  var audioURL: URL?
  var notes = ""
  /// People tagged on this recording.
  var participantIDs: [UUID]? = nil
  /// Small JPEGs attached to the record.
  var photoData: [Data]? = nil
}

extension Meeting {
  private enum CodingKeys: String, CodingKey {
    case id
    case title
    case createdAt
    case duration
    case source
    case status
    case summary
    case keyPoints
    case decisions
    case openQuestions
    case transcript
    case spaceID
    case audioURL
    case notes
    case participantIDs
    case photoData
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    title = try container.decode(String.self, forKey: .title)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
    duration = try container.decode(TimeInterval.self, forKey: .duration)
    source = try container.decode(MeetingSource.self, forKey: .source)
    status = try container.decode(MeetingStatus.self, forKey: .status)
    summary = try container.decode(String.self, forKey: .summary)
    keyPoints = try container.decode([String].self, forKey: .keyPoints)
    decisions = try container.decode([String].self, forKey: .decisions)
    openQuestions = try container.decode([String].self, forKey: .openQuestions)
    transcript = try container.decode([TranscriptSegment].self, forKey: .transcript)
    spaceID = try container.decodeIfPresent(UUID.self, forKey: .spaceID)
    notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    participantIDs = try container.decodeIfPresent([UUID].self, forKey: .participantIDs)
    photoData = try container.decodeIfPresent([Data].self, forKey: .photoData)

    // Stored as a path relative to the media folder since 2.x; older records
    // hold an absolute path, which is only kept when it resolves to a file the
    // app still manages.
    if let stored = try container.decodeIfPresent(String.self, forKey: .audioURL) {
      audioURL = MediaFiles.resolve(stored)
    } else {
      audioURL = nil
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(title, forKey: .title)
    try container.encode(createdAt, forKey: .createdAt)
    try container.encode(duration, forKey: .duration)
    try container.encode(source, forKey: .source)
    try container.encode(status, forKey: .status)
    try container.encode(summary, forKey: .summary)
    try container.encode(keyPoints, forKey: .keyPoints)
    try container.encode(decisions, forKey: .decisions)
    try container.encode(openQuestions, forKey: .openQuestions)
    try container.encode(transcript, forKey: .transcript)
    try container.encodeIfPresent(spaceID, forKey: .spaceID)
    try container.encode(notes, forKey: .notes)
    try container.encodeIfPresent(participantIDs, forKey: .participantIDs)
    try container.encodeIfPresent(photoData, forKey: .photoData)

    if let audioURL, let reference = MediaFiles.reference(for: audioURL) {
      try container.encode(reference, forKey: .audioURL)
    }
  }
}


extension Meeting {
  /// True when the engine identified at least one speaker. Engines that cannot
  /// separate speakers leave every segment uncertain, so the transcript reads as
  /// continuous text instead of a back-and-forth.
  var hasSpeakerSeparation: Bool {
    transcript.contains { $0.speakerIsCertain }
  }
}

enum MeetingSource: String, Hashable, Codable {
  case recording
  case importFile

  var label: String {
    switch self {
    case .recording:
      "録音"
    case .importFile:
      "インポート"
    }
  }
}

enum MeetingStatus: Hashable, Codable {
  case waitingForTranscription
  case waitingForSummary
  case importing(Double)
  case transcribing(Double)
  case organizing(String)
  case ready
  case partialFailure(String)
  case failed(String)

  var shortLabel: String {
    switch self {
    case .waitingForTranscription:
      "未処理"
    case .waitingForSummary:
      "要約待ち"
    case .importing(let progress):
      "読み込み \(Int(progress * 100))%"
    case .transcribing(let progress):
      "文字起こし \(Int(progress * 100))%"
    case .organizing:
      "整理中"
    case .ready:
      "整理済み"
    case .partialFailure:
      "一部未完了"
    case .failed:
      "要確認"
    }
  }

  var symbol: String {
    switch self {
    case .waitingForTranscription:
      "waveform.badge.plus"
    case .waitingForSummary:
      "sparkles"
    case .importing:
      "arrow.down.doc"
    case .transcribing:
      "text.bubble"
    case .organizing:
      "sparkles"
    case .ready:
      "checkmark"
    case .partialFailure:
      "exclamationmark.triangle"
    case .failed:
      "arrow.clockwise"
    }
  }
}
