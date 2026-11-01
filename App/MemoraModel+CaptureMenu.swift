import Foundation

extension MemoraModel {
  func performCaptureMenuAction(_ action: CaptureAction, projectID: UUID?) async {
    switch action {
    case .recording: await startCapture(spaceID: projectID)
    case .newMemo:
      guard LocalImportContext(projectID: projectID, in: self) != nil else { return }
      sourceAddProjectID = projectID
      sourceAddAsMemo = true
      isSourceAddPresented = true
    case .newChat:
      selectedTab = .askAI
      startNewAIChat()
    case .phoneCall: openCalling()
    case .onlineMeeting:
      onlineMeetingCaptureSpaceID = projectID
      isOnlineMeetingCapturePresented = true
    case .importAudio: break
    }
  }
}
