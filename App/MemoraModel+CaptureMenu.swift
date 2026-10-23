import Foundation

extension MemoraModel {
  func performCaptureMenuAction(_ action: CaptureAction, projectID: UUID?) async {
    switch action {
    case .recording: await startCapture(spaceID: projectID)
    case .newMemo: isLifeLogCreationPresented = true
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
