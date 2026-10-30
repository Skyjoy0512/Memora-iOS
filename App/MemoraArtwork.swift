enum MemoraArtwork: String, CaseIterable {
  case askAITab = "ask-ai-tab"
  case askAIHeader = "ask-ai-header"
  case signIn = "sign-in"
  case settingsTranscription = "settings-transcription"
  case settingsIntelligence = "settings-intelligence"
  case settingsResidentAgent = "settings-resident-agent"
  case settingsMemory = "settings-memory"
  case settingsSummary = "settings-summary"
  case settingsWebhook = "settings-webhook"
  case settingsMCP = "settings-mcp"
  case settingsStorage = "settings-storage"
  case settingsMemoraIntelligence = "settings-memora-intelligence"
  case settingsLocalModel = "settings-local-model"
  case settingsRegisteredModels = "settings-registered-models"
  case settingsAPIKey = "settings-api-key"
  case settingsProvider = "settings-provider"
  case settingsNotion = "settings-notion"
  case settingsGmail = "settings-gmail"
  case settingsCredits = "settings-credits"
  case settingsLicense = "settings-license"
  case settingsTeam = "settings-team"
  case settingsSignUp = "settings-sign-up"
  case settingsPlan = "settings-plan"
  case searchIntelligence = "search-intelligence"
  case journalTab = "journal-tab"
  case journalTabSolid = "journal-tab-solid"
  case askAITabSolid = "ask-ai-tab-solid"
  case folderSolid = "folder-solid"
  case insightQuestion = "insight-question"
  case insightSummary = "insight-summary"
  case insightTarget = "insight-target"
  case voiceInput = "voice-input"
  case editorBody = "editor-body"
  case editorHeading = "editor-heading"
  case editorBold = "editor-bold"
  case editorItalic = "editor-italic"
  case editorList = "editor-list"
  case editorChecklist = "editor-checklist"
  case editorCheck = "editor-check"
  case editorTable = "editor-table"

  var icon: MemoraIcon {
    switch self {
    case .askAITab, .askAIHeader, .askAITabSolid: .chatBubble
    case .signIn, .settingsSignUp: .personCropCircle
    case .settingsTranscription, .voiceInput: .mic
    case .settingsIntelligence, .settingsMemoraIntelligence: .brain
    case .settingsResidentAgent: .personBadgeKey
    case .settingsMemory: .brainHeadProfile
    case .settingsSummary, .insightSummary: .docText
    case .settingsWebhook: .link
    case .settingsMCP: .plugsConnected
    case .settingsStorage: .internaldrive
    case .settingsLocalModel: .cpu
    case .settingsRegisteredModels: .rectangleStack
    case .settingsAPIKey: .key
    case .settingsProvider: .cloud
    case .settingsNotion: .notionLogo
    case .settingsGmail: .envelope
    case .settingsCredits: .boltFill
    case .settingsLicense: .checkmarkSeal
    case .settingsTeam: .person3
    case .settingsPlan: .crown
    case .searchIntelligence: .magnifyingglass
    case .journalTab, .journalTabSolid: .calendar
    case .folderSolid: .folder
    case .insightQuestion: .questionmarkBubble
    case .insightTarget: .pin
    case .editorBody: .textAlignleft
    case .editorHeading: .heading
    case .editorBold: .bold
    case .editorItalic: .italic
    case .editorList: .listBulletRectangle
    case .editorChecklist: .checklist
    case .editorCheck: .checkmark
    case .editorTable: .tablecells
    }
  }
}
