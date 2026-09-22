import CloudKit
import Foundation
import Observation

/// Shares projects and records with a team through CloudKit, and reads what has
/// been shared with this person. The local store stays the source of truth: a
/// shared item is a snapshot the owner publishes, and teammates see it in a
/// read-only list that updates when the owner changes it.
///
/// CloudKit needs the iCloud capability and a container that match this build's
/// bundle identifier. When they are missing, or no iCloud account is signed in,
/// the service says so instead of pretending a share happened. Nothing here runs
/// until the person asks to share, so a build without the capability still
/// launches normally.
@MainActor
@Observable
final class CloudSharingService {
  static let shared = CloudSharingService()

  enum Availability: Equatable {
    case unknown
    case available
    case noAccount
    case unavailable(String)
  }

  /// A share ready to be presented in the system sharing sheet.
  struct ShareRequest: Identifiable {
    let id = UUID()
    var share: CKShare
    var container: CKContainer
    var title: String
  }

  /// A project or record someone else has shared with this person.
  struct ReceivedItem: Identifiable, Equatable {
    var id: String
    var title: String
    var kind: String
    var updatedAt: Date
    var payload: Data
  }

  private(set) var availability: Availability = .unknown
  private(set) var receivedItems: [ReceivedItem] = []
  private(set) var isWorking = false
  var errorMessage: String?

  static let recordType = "MemoraSharedItem"
  static let zoneName = "MemoraTeam"
  private static let subscriptionID = "memora-shared-items"

  /// The container must match the iCloud entitlement; it is derived from the
  /// bundle identifier so there is one place to keep them in step.
  static var containerID: String {
    "iCloud." + (Bundle.main.bundleIdentifier ?? "app.bitrig.new.memora")
  }

  @ObservationIgnored private var containerStorage: CKContainer?
  @ObservationIgnored private var didSubscribe = false

  private var container: CKContainer {
    if let containerStorage { return containerStorage }
    let created = CKContainer(identifier: Self.containerID)
    containerStorage = created
    return created
  }

  private var privateDatabase: CKDatabase { container.privateCloudDatabase }
  private var sharedDatabase: CKDatabase { container.sharedCloudDatabase }

  /// The iCloud account and container state, checked without touching CloudKit
  /// when iCloud is not set up at all.
  func refreshAvailability() async {
    guard FileManager.default.ubiquityIdentityToken != nil else {
      availability = .noAccount
      return
    }
    do {
      switch try await container.accountStatus() {
      case .available:
        availability = .available
      case .noAccount, .restricted:
        availability = .noAccount
      case .couldNotDetermine, .temporarilyUnavailable:
        availability = .unavailable("iCloudの状態を確認できませんでした。")
      @unknown default:
        availability = .unavailable("iCloudを利用できません。")
      }
    } catch {
      availability = .unavailable("このビルドにはiCloudコンテナが設定されていません。")
    }
  }

  /// Publishes a snapshot and returns a share to invite people with. Saving both
  /// the record and its share is atomic, so a share never exists without its
  /// content.
  func makeShare(title: String, kind: String, payload: Data) async throws -> ShareRequest {
    isWorking = true
    defer { isWorking = false }

    let zone = CKRecordZone(zoneName: Self.zoneName)
    _ = try? await privateDatabase.save(zone)

    let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zone.zoneID)
    let record = CKRecord(recordType: Self.recordType, recordID: recordID)
    record["title"] = title as CKRecordValue
    record["kind"] = kind as CKRecordValue
    record["payload"] = payload as CKRecordValue
    record["updatedAt"] = Date() as CKRecordValue

    let share = CKShare(rootRecord: record)
    share[CKShare.SystemFieldKey.title] = title as CKRecordValue

    let outcome = try await privateDatabase.modifyRecords(
      saving: [record, share],
      deleting: [],
      savePolicy: .ifServerRecordUnchanged,
      atomically: true
    )
    guard let saved = try outcome.saveResults[share.recordID]?.get() as? CKShare else {
      throw CloudSharingError.saveFailed
    }
    try? await subscribeIfNeeded()
    return ShareRequest(share: saved, container: container, title: title)
  }

  /// Updates a snapshot the owner already shared, so teammates see the change.
  func updateShare(recordName: String, payload: Data) async throws {
    let recordID = CKRecord.ID(recordName: recordName, zoneID: CKRecordZone(zoneName: Self.zoneName).zoneID)
    let record = try await privateDatabase.record(for: recordID)
    record["payload"] = payload as CKRecordValue
    record["updatedAt"] = Date() as CKRecordValue
    _ = try await privateDatabase.save(record)
  }

  /// Accepts a share the person opened from the system, then refreshes the list.
  func accept(_ metadata: CKShare.Metadata) async {
    do {
      _ = try await container.accept(metadata)
      await refreshReceived()
    } catch {
      errorMessage = "共有を受け取れませんでした。iCloudの状態を確認してください。"
    }
  }

  /// Reads the items shared with this person. Safe to call whenever the screen
  /// appears or the app returns to the foreground.
  func refreshReceived() async {
    guard availability == .available else { return }
    do {
      let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
      let outcome = try await sharedDatabase.records(matching: query)
      var items: [ReceivedItem] = []
      for (_, result) in outcome.matchResults {
        guard case .success(let record) = result else { continue }
        items.append(
          ReceivedItem(
            id: record.recordID.recordName,
            title: record["title"] as? String ?? "共有アイテム",
            kind: record["kind"] as? String ?? "",
            updatedAt: record["updatedAt"] as? Date ?? .now,
            payload: record["payload"] as? Data ?? Data()
          )
        )
      }
      receivedItems = items.sorted { $0.updatedAt > $1.updatedAt }
    } catch {
      errorMessage = "共有された項目を読み込めませんでした。"
    }
  }

  /// Subscribes once to changes in shared items, so a teammate's edit arrives as
  /// a silent push. It also refreshes on foreground, so a missing push
  /// entitlement still leaves the list current.
  private func subscribeIfNeeded() async throws {
    guard !didSubscribe else { return }
    let subscription = CKQuerySubscription(
      recordType: Self.recordType,
      predicate: NSPredicate(value: true),
      subscriptionID: Self.subscriptionID,
      options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
    )
    let info = CKSubscription.NotificationInfo()
    info.shouldSendContentAvailable = true
    subscription.notificationInfo = info
    _ = try? await sharedDatabase.save(subscription)
    didSubscribe = true
  }

  var availabilityMessage: String? {
    switch availability {
    case .available, .unknown:
      nil
    case .noAccount:
      "チーム共有にはiCloudへのサインインが必要です。設定のApple IDからサインインしてください。"
    case .unavailable(let reason):
      reason
    }
  }
}

enum CloudSharingError: LocalizedError {
  case saveFailed

  var errorDescription: String? {
    switch self {
    case .saveFailed:
      "共有を作成できませんでした。iCloudの状態を確認してください。"
    }
  }
}
