import AppIntents

struct MemoraAppShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: OpenAskAIIntent(), phrases: ["\(.applicationName)でAIに質問"], shortTitle: "Ask AI", systemImageName: "bubble.left.and.bubble.right")
    AppShortcut(intent: StartMemoraRecordingIntent(), phrases: ["\(.applicationName)で録音を開始"], shortTitle: "録音を開始", systemImageName: "waveform")
    AppShortcut(intent: OpenMemoraMemoIntent(), phrases: ["\(.applicationName)でメモを書く"], shortTitle: "メモを書く", systemImageName: "square.and.pencil")
    AppShortcut(intent: OpenMemoraTasksIntent(), phrases: ["\(.applicationName)の今日のタスクを開く"], shortTitle: "今日のタスク", systemImageName: "checklist")
    AppShortcut(intent: OpenMemoraJournalIntent(), phrases: ["\(.applicationName)のジャーナルを開く"], shortTitle: "ジャーナル", systemImageName: "calendar")
    AppShortcut(intent: OpenMemoraProjectIntent(), phrases: ["\(.applicationName)で\(\.$target)を開く"], shortTitle: "プロジェクト", systemImageName: "folder")
  }
}
