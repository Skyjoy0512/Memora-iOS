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
    /// Who shared it, so the item never reads as one of this person's own.
    var ownerName: String
  }

  private(set) var availability: Availability = .unknown {
    didSet {
      // Remembered once CloudKit has answered, so later launches can read
      // shared items on their own without first touching an unconfigured
      // container, which would stop the app.
      if availability == .available, !Self.hasConfirmedContainer {
        UserDefaults.standard.set(true, forKey: Self.confirmedContainerKey)
      }
    }
  }
  private(set) var receivedItems: [ReceivedItem] = []
  /// Records shared one by one, and records inside shared projects, ready to
  /// list. Built once per refresh, so screens do not decode on every redraw.
  private(set) var sharedRecords: [SharedRecord] = []
  private(set) var sharedProjects: [SharedProject] = []
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

  private static let confirmedContainerKey = "memora.teamSharing.containerConfirmed"

  static var hasConfirmedContainer: Bool {
    UserDefaults.standard.bool(forKey: confirmedContainerKey)
  }

  /// Reads shared items in the background of a screen, but only on a device
  /// where sharing has already worked; elsewhere it waits for the person to
  /// open team sharing.
  func refreshIfConfirmed() async {
    guard Self.hasConfirmedContainer else { return }
    await refreshAvailability()
    await refreshReceived()
  }

  func sharedRecord(id: String) -> SharedRecord? {
    sharedRecords.first { $0.id == id }
      ?? sharedProjects.lazy.flatMap(\.records).first { $0.id == id }
  }

  func sharedProject(id: String) -> SharedProject? {
    sharedProjects.first { $0.id == id }
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
  func makeShare(title: String, kind: String, payload: Data, ownerName: String) async throws -> ShareRequest {
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
    record["ownerName"] = ownerName as CKRecordValue

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
  /// appears or the app returns to the foreground. The shared database only
  /// answers queries zone by zone, one zone per person sharing.
  func refreshReceived() async {
    guard availability == .available else { return }
    do {
      let zones = try await sharedDatabase.allRecordZones()
      var records: [CKRecord] = []
      for zone in zones {
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        let outcome = try await sharedDatabase.records(matching: query, inZoneWith: zone.zoneID)
        for (_, result) in outcome.matchResults {
          if case .success(let record) = result { records.append(record) }
        }
      }
      let owners = await shareOwnerNames(for: records)

      let items = records.map { record in
        let written = (record["ownerName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ReceivedItem(
          id: record.recordID.recordName,
          title: record["title"] as? String ?? "共有アイテム",
          kind: record["kind"] as? String ?? "",
          updatedAt: record["updatedAt"] as? Date ?? .now,
          payload: record["payload"] as? Data ?? Data(),
          ownerName: owners[record.recordID] ?? (written.isEmpty ? "チームのメンバー" : written)
        )
      }
      .sorted { $0.updatedAt > $1.updatedAt }

      guard items != receivedItems else { return }
      receivedItems = items
      rebuildShared()
    } catch {
      errorMessage = "共有された項目を読み込めませんでした。"
    }
  }

  /// The name iCloud gives the person who owns each share. It is preferred
  /// over the name written into the record, which the owner chose in Memora.
  private func shareOwnerNames(for records: [CKRecord]) async -> [CKRecord.ID: String] {
    let shareIDs = records.compactMap { $0.share?.recordID }
    guard !shareIDs.isEmpty,
          let results = try? await sharedDatabase.records(for: shareIDs) else { return [:] }

    var names: [CKRecord.ID: String] = [:]
    for record in records {
      guard let shareID = record.share?.recordID,
            case .success(let fetched)? = results[shareID],
            let share = fetched as? CKShare,
            let components = share.owner.userIdentity.nameComponents else { continue }
      let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
      if !name.isEmpty { names[record.recordID] = name }
    }
    return names
  }

  /// Opens each snapshot once, into the records and projects the screens list.
  private func rebuildShared() {
    let decoder = JSONDecoder()
    var records: [SharedRecord] = []
    var projects: [SharedProject] = []
    for item in receivedItems {
      guard let snapshot = try? decoder.decode(TeamShareSnapshot.self, from: item.payload) else { continue }
      let shared = snapshot.meetings.map { meeting in
        SharedRecord(
          itemID: item.id,
          meeting: meeting,
          tasks: snapshot.tasks.filter { $0.meetingID == meeting.id },
          ownerName: item.ownerName,
          projectName: snapshot.space?.name,
          updatedAt: item.updatedAt
        )
      }
      switch snapshot.kind {
      case .meeting:
        records.append(contentsOf: shared)
      case .project:
        projects.append(
          SharedProject(
            id: item.id,
            name: snapshot.space?.name ?? item.title,
            icon: snapshot.space?.icon ?? .folder,
            ownerName: item.ownerName,
            updatedAt: item.updatedAt,
            records: shared.sorted { $0.meeting.createdAt > $1.meeting.createdAt }
          )
        )
      }
    }
    sharedRecords = records.sorted { $0.meeting.createdAt > $1.meeting.createdAt }
    sharedProjects = projects
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
