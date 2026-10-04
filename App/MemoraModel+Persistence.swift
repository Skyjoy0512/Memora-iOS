import Foundation

extension MemoraModel {
  /// While the store is protected, every change that would write over data that
  /// could not be read is stopped — including deletes, restores, and the removal
  /// of files, which would otherwise leave the store and the media disagreeing.
  /// Returns false, and says why, when the change must not happen.
  func isStoreWritable() -> Bool {
    guard !isStoreProtected else {
      persistenceFailureMessage = storeProtectedMessage
      return false
    }
    return true
  }

  func persistPendingMediaDeletions() {
    persistInBackground(pendingMediaDeletions, forKey: StorageKey.pendingMediaDeletions)
  }

  func persistAIHistory() {
    persistInBackground(aiHistory, forKey: StorageKey.aiHistory)
  }

  func persistAIMemories() {
    persistInBackground(aiMemories, forKey: StorageKey.aiMemories)
  }

  func persistTasks() {
    persistInBackground(tasks, forKey: StorageKey.tasks)
  }

  func persistLifeLog() {
    persistInBackground(lifeLogEntries, forKey: StorageKey.lifeLogEntries)
  }

  func persistMeetings() {
    let startedAt = Date()
    defer {
      performance.record(
        "保存（会議の引き渡し）",
        milliseconds: Date.now.timeIntervalSince(startedAt) * 1_000,
        count: meetings.count
      )
    }
    persistInBackground(meetings, forKey: StorageKey.meetings)
  }

  func persistSpaces() {
    persistInBackground(spaces, forKey: StorageKey.spaces)
  }

  func persistDocuments() {
    persistInBackground(documents, forKey: StorageKey.documents)
  }

  func persistInBackground<T: Encodable & Sendable>(_ value: T, forKey key: String) {
    // A store that could not be read must not be written over: the existing
    // records may still be there, and replacing them would lose them.
    guard isStoreWritable() else { return }
    RecordStore.save(value, key: key) { [weak self] in
      self?.persistenceFailureMessage = self?.saveFailureMessage
    }
  }

  /// Waits for the write and reports whether it worked, for operations that must
  /// know before doing anything else.
  @discardableResult
  func persistNow<T: Encodable>(_ value: T, forKey key: String) -> Bool {
    guard isStoreWritable() else { return false }
    do {
      try RecordStore.saveNow(value, key: key)
      return true
    } catch {
      persistenceFailureMessage = saveFailureMessage
      return false
    }
  }

  /// Waits for a write of several documents that belong to one operation, and
  /// reports whether all of them landed. `removing` lets the same commit discard
  /// the draft that belongs to the operation.
  @discardableResult
  func persistBatch(
    _ build: () throws -> [(key: String, data: Data)],
    removing: [String] = []
  ) -> Bool {
    guard isStoreWritable() else { return false }
    do {
      try RecordStore.commitNow(writes: try build(), removing: removing)
      return true
    } catch {
      persistenceFailureMessage = saveFailureMessage
      return false
    }
  }

  /// The same commit, off the caller's turn, for a screen that must not wait on
  /// disk while it finishes.
  @discardableResult
  func persistBatchAsync(
    _ build: () throws -> [(key: String, data: Data)],
    removing: [String] = []
  ) async -> Bool {
    guard isStoreWritable() else { return false }
    do {
      try await RecordStore.commitAsync(writes: try build(), removing: removing)
      return true
    } catch {
      persistenceFailureMessage = saveFailureMessage
      return false
    }
  }

  /// Stores one document and waits for it, without blocking the caller while the
  /// write is in flight.
  @discardableResult
  func persistNowAsync<T: Encodable>(_ value: T, forKey key: String) async -> Bool {
    guard isStoreWritable() else { return false }
    do {
      let data = try RecordStore.encoded(value)
      try await RecordStore.commitAsync(writes: [(key: key, data: data)], removing: [])
      return true
    } catch {
      persistenceFailureMessage = saveFailureMessage
      return false
    }
  }

  private var saveFailureMessage: String {
    "データを保存できませんでした。ストレージの空き容量を確認してください。"
  }

  private var storeProtectedMessage: String {
    "保存データを読み込めなかったため、上書きを止めています。アプリを再起動してください。"
  }

  enum StorageKey {
    static let currentTeamID = "memora.workspace.currentTeam"
    static let hasCompletedOnboarding = "hasSeenMemoraWelcome"
    static let hasOfferedPlus = "hasOfferedMemoraPlus"
    static let isSubscribed = "memoraPlusActive"
    static let planTier = "memoraPlanTier"
    static let plan = "memora.plan"
    static let account = "memoraAccount"
    static let tasks = "memoraTasks"
    static let lifeLogEntries = "memoraLifeLogEntries"
    static let meetings = "memoraMeetings"
    static let spaces = "memoraSpaces"
    static let aiEngine = "memora.aiEngine"
    static let aiProvider = "memora.aiProvider"
    static func aiModel(_ provider: LLMProvider) -> String { "memora.aiModel.\(provider.rawValue)" }
    static let people = "memoraPeople"
    static let installedTemplates = "memoraInstalledTemplates"
    static let cloudStorage = "memoraCloudStorage"
    static let activeJobs = "memoraActiveJobs"
    static let recordingDraft = "memoraRecordingDraft"
    static let trash = "memoraTrash"
    static let lifeLogTrash = "memoraLifeLogTrash"
    static let aiHistory = "memoraAIHistory"
    static let aiMemories = "memoraAIMemories"
    static let aiThread = "memoraAIThread"
    static let aiMemoryEnabled = "memora.ai.memoryEnabled"
    static let glossary = "memora.glossary"
    static let verifiedCallerNumber = "memora.calling.verifiedNumber"
    static let customTemplates = "memoraCustomTemplates"
    static let webhooks = "memora.integrations.webhooks"
    static let mcpServers = "memora.integrations.mcpServers"
    static let defaultTemplate = "memora.summary.defaultTemplate"
    static let pendingMediaDeletions = "memoraPendingMediaDeletions"
    static let documents = "memoraDocuments"
    static let hasOfferedSampleDeletion = "memora.hasOfferedSampleDeletion"
    static let autoLifeLogInbox = "memoraAutoLifeLogInbox"
  }
}

extension MemoraModel {
  /// A small settings value kept as JSON in UserDefaults.
  static func storedSetting<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
    UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
  }

  static func storeSetting<T: Encodable>(_ value: T, forKey key: String) {
    UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
  }
}
