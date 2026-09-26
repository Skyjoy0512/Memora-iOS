import Foundation

struct Meeting: Identifiable, Hashable, Codable {
  var id: UUID
  var title: String
  var createdAt: Date

  /// Never empty where a name is required, such as the system now-playing
  /// controls, without changing what is stored.
  var displayTitle: String {
    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "無題の記録" : title
  }

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
  /// File names of the photos attached to the record, inside the media folder.
  var photoFileNames: [String]? = nil
  /// The calendar event the recording was started from, when it was.
  var calendarEventID: String? = nil
  /// Photos older records held inline, kept until they are written to files.
  /// Decoding never writes to the app's folders, so reading a backup is free of
  /// side effects; `materializeLegacyPhotos()` does the writing afterwards.
  var legacyPhotoData: [Data]? = nil
  /// The audio reference exactly as it was stored, before it was turned into a
  /// URL. A backup checks this raw value, so an unsafe reference is refused
  /// instead of quietly resolving to nil.
  var rawAudioReference: String? = nil
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
    case photoFileNames
    case calendarEventID
    /// Legacy: photos used to be stored inline in the record.
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
    calendarEventID = try container.decodeIfPresent(String.self, forKey: .calendarEventID)

    // Photos moved out of the record and into the media folder. Older records
    // carry the bytes inline; they are kept for now and written out by
    // `materializeLegacyPhotos()` on the app's own records, never while a backup
    // is only being read.
    if let names = try container.decodeIfPresent([String].self, forKey: .photoFileNames) {
      photoFileNames = names.isEmpty ? nil : names
      legacyPhotoData = nil
    } else if let legacy = try container.decodeIfPresent([Data].self, forKey: .photoData), !legacy.isEmpty {
      photoFileNames = nil
      legacyPhotoData = legacy
    } else {
      photoFileNames = nil
      legacyPhotoData = nil
    }

    // Stored as a path relative to the media folder since 2.x; older records
    // hold an absolute path, which is only kept when it resolves to a file the
    // app still manages. The raw value is kept so a backup can check it.
    rawAudioReference = try container.decodeIfPresent(String.self, forKey: .audioURL)
    if let stored = rawAudioReference {
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
    try container.encodeIfPresent(calendarEventID, forKey: .calendarEventID)

    // A record still waiting to have its inline photos written keeps the bytes,
    // so a save in between does not drop them. Once they are files, the names
    // are what is stored.
    if let photoFileNames {
      try container.encodeIfPresent(photoFileNames, forKey: .photoFileNames)
    } else if let legacy = legacyPhotoData, !legacy.isEmpty {
      try container.encode(legacy, forKey: .photoData)
    }

    if let audioURL, let reference = MediaFiles.reference(for: audioURL) {
      try container.encode(reference, forKey: .audioURL)
    }
  }
}


extension Meeting {
  /// Writes photos that an older record held inline and turns them into file
  /// names. Called on the app's own records after loading, never during a decode.
  /// Returns false when a photo could not be written: the original bytes are all
  /// kept and any files just written are removed, so a retry neither loses the
  /// photo nor leaves a duplicate behind. A later save stores the bytes again.
  @discardableResult
  mutating func materializeLegacyPhotos() -> Bool {
    guard let legacy = legacyPhotoData, !legacy.isEmpty else { return true }

    var names: [String] = []
    for data in legacy {
      guard let name = MediaFiles.writePhoto(data) else {
        for written in names {
          MediaFiles.deletePhoto(written)
        }
        return false
      }
      names.append(name)
    }
    photoFileNames = names.isEmpty ? nil : names
    legacyPhotoData = nil
    return true
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

  var symbol: MemoraIcon {
    switch self {
    case .waitingForTranscription:
      .waveformBadgePlus
    case .waitingForSummary:
      .sparkles
    case .importing:
      .arrowDownDoc
    case .transcribing:
      .textBubble
    case .organizing:
      .sparkles
    case .ready:
      .checkmark
    case .partialFailure:
      .exclamationmarkTriangle
    case .failed:
      .arrowClockwise
    }
  }
}
