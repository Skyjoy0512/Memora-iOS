import Foundation

extension MemoraModel {
  func saveMeetingToNotion(_ id: UUID, environment: NotionSaveEnvironment) async throws -> NotionService.Outcome {
    guard let export = NotionExportContext(in: self, meetingID: id, scope: .all) else {
      throw NotionService.Failure.authorizationChanged
    }
    guard let configuration = environment.configuration() else { throw NotionService.Failure.missingConfig }
    return try await saveNotionExport(export, configuration: configuration, environment: environment)
  }

  func saveNotionExport(_ export: NotionExportContext, configuration: NotionSaveConfiguration,
    environment: NotionSaveEnvironment, isAuthorized: @escaping @MainActor @Sendable () -> Bool = { true }
  ) async throws -> NotionService.Outcome {
    let current: @MainActor @Sendable () -> Bool = { [weak self] in
      guard let self else { return false }
      return export.isCurrent(in: self) && isAuthorized()
    }
    guard current() else { throw NotionService.Failure.authorizationChanged }
    return try await NotionService.save(meeting: export.meeting, tasks: export.tasks, configuration: {
      let value = environment.configuration()
      return value == configuration ? value : nil
    }, transport: environment.transport, isAuthorized: current)
  }
}
