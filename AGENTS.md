# AGENTS.md — Memora

SwiftUI app for iPhone (iOS 26 deployment target, built against the iOS 27 SDK).
App sources live in `App/`, configuration in `Project.json`, design notes in
`DESIGN.md` and `MCP.md`.

## Working agreement

- When asked to delegate implementation to OpenCode Go, act as the supervisor:
  inspect scope and read `docs/CODEX_OPENCODE_WORKFLOW.md`, then invoke
  `/opt/homebrew/bin/python3.12 tools/supervisor/run.py` with a bounded task
  and exact `--allow-file` paths. Use `--apply` when integrating the passing
  candidate is requested. Review the resulting diff, run task-specific checks,
  and commit only the intended files. Never claim visual/device validation from
  compilation alone. Do not bypass failed gates or exceed two repair attempts.
  After applying changes that affect the app, run `bitrig preview -platform iOS`
  from the Bitrig agent session to update the user's preview.

- Change the UI, layout, or copy only when the request asks for it. Otherwise
  optimise and refactor code without altering what is on screen.
- Build after every change and keep the working tree committed.
- Records live in the SQLite store (`App/LocalStore.swift`); only settings belong
  in `UserDefaults`. Audio and photos are files under the app container, referenced
  from a record by name (`App/MediaFiles.swift`); never inline the bytes again.
- One type per file; comments explain why, not what; prefer `var` for stored
  properties in structs; no `#Preview` or `PreviewProvider`.
- `MemoraModel.swift` holds only stored state, loading and the derived indexes.
  Behaviour lives in `MemoraModel+<Domain>.swift` (Capture, Processing, Import,
  Meetings, Tasks, Journal, Trash, Media, Backup, Persistence, …); add new
  model code to the matching extension. Derived values that screens observe
  (aggregates, journal days, the samples flag) are assigned only when they
  change, so an unrelated edit does not redraw every screen reading them.
- In view bodies, compute a filtered or searched list once (`let` at the top of
  `body`) and pass it down; never re-derive it per row. Fast-ticking values
  (recording time, playback position) are read only in small leaf views.

## Known regressions to avoid

- **Navigation**: there is no bottom tab bar. The app opens on Library, and the
  destinations (Journal, Library, Ask AI, Marketplace) live at the top of the side menu
  (`FileSidebarView`). The bottom edge holds Ask AI with the two independent capture controls. `RootTab` still names
  the destination and keeps the old saved identifiers, but nothing draws tabs.
- **Create controls**: the idle bottom row is Ask AI / memo / microphone.
  `CaptureFloatingButtons` presents two native menus from `CaptureMenuPopover`:
  memo has メモを書く / 資料を追加; microphone has 録音する / 音声を取り込む /
  オンライン会議を録音, with recording first. Do not restore the top-right ＋.
  While composing, give Ask AI the full row; hide capture controls without
  unmounting their file importer. Empty states reuse the full native dialog.
  Project creation stays in Projects' options menu and empty state; a project's
  new chat stays in its options and chat empty state.
- **Files screen top chrome**: do not drive the navigation bar's visibility from
  a scroll-offset flag. Hiding and showing the bar from that state re-runs
  layout, which is read back as more scrolling and freezes the screen. The
  Library tab lists records across all projects; projects are opened and
  created in the Library's Projects segment (`ProjectsView`); both segments
  share one `libraryPath`. Persist the selected `LibrarySection` as a setting.
- **Bottom edge**: Ask AI and the capture controls stay at the bottom; scrolling moves no
  navigation bar because there is none. Search and file selection still hide
  the composer and capture controls so results or the share / move / delete bar own the bottom edge.
- **Search**: the side menu's Search action searches the current destination.
  Files, Journal and Tools open `ToolbarSearchField`; Ask AI opens its existing
  conversation search sheet. The former root search toolbar slot belongs to
  `RecorderStatusToolbarButton`, which opens the existing recorder hub. Battery
  values come only from the connected recorder, never the phone or a fixture.
  While the toolbar field is open (`isSearchActive`), the composer hides and the screen shows only results,
  never the list behind them. Do not bring back an always-visible `.searchable`
  drawer. Picking files on Files (`isFileSelectionActive`) hides the composer
  the same way, so the share / move / delete bar owns the bottom edge.
- **Marketplace**: `ToolsView` retains the saved Tools destination and opens
  マーケットプレイス from the side menu. It shows a featured recommendation and
  skill/template/integration shelves. Cards open the existing details; すべて見る
  opens each full catalog. Home search spans all three catalogs and custom items;
  category search stays scoped. Creation/import, template management and MCP
  registration remain reachable through native menus and the Settings editors.
  Community publishing uses the Firebase REST client and server implementation in
  `backend/marketplace`. Until `MemoraMarketplaceURL` and `MemoraFirebaseAPIKey` are
  configured and deployed, show it as unavailable; never fabricate posts or counts.
  Definitions are reviewed before publication. Only the server changes counts;
  additions require a receipt and confirmed local save. Shared definitions never
  grant tool permissions or include meeting/chat data. Ask AI's plus and the
  marketplace use the same connector hub/detail sheet and existing setup routes.
- **Tasks**: `TasksView` lives inside Home's NavigationStack (`.tasks` route),
  including notification navigation. Keep creation, editing and source links reachable.
- **Project context**: capture uses `visibleProjectID` from the active navigation
  path. Ask AI uses global scope on its tab, project scope on a project detail,
  and record scope on a meeting/transcript. Shared projects remain read-only.
- **Journal (Home)**: the screen's own `ScrollView`/`List` must stay its
  primary scroll view, so the large title collapses the way the system expects.

## Known gaps (not bugs to fix silently)

- Cloud storage, the ChatGPT (MCP) server screen, Google Drive, on-device
  Whisper and local LLM are preferences only; the services behind them are not implemented. The app says
  so rather than returning sample results.
- Recording, transcription and summarization never fill in sample content: when
  no engine can run, the record keeps its audio and shows the failure with a
  retry.
- Text being edited inline keeps a draft (`DraftStore`), restored next time that editor opens.
- A recording in progress keeps a draft; if the app stops, the audio is recovered
  as its own record and is never re-recorded automatically. Voice input is
  refused (with a reason) while a recording owns the audio session.
- Sign-in and purchase are not connected: the screens say so, and no account is
  created from them. Plans are ライト / Pro / アンリミテッド / チーム (`MemoraPlan`,
  `choosePlan`, a local preference until StoreKit is connected); each caps its
  Memora Intelligence credits and cloud transcription so that, used to the
  full, it costs less than it earns — the numbers and the conditions that keep
  it so are in `docs/PRICING.md`. A company license (`MemoraLicense`) is a code
  signed with Ed25519 (`LicenseCodeVerifier`, public key under the Info.plist
  key `MemoraLicensePublicKey`, codes issued with `tools/memora-license.swift`;
  the private key never enters the repository); it outranks the personal plan
  (`effectivePlan`). Team features need the team plan or a license
  (`hasTeamPlan`). Transcription is on-device only on every plan for now.
  `MemoraAccount` stays in the model for a later phase.
- Memora Intelligence (`AIEngine.memora`, `MemoraIntelligence`) is the
  OpenAI-compatible cloud path pointed at Memora's own server
  (`MemoraIntelligenceURL` in Info.plist) with a server-issued token; the server
  holds the DeepSeek key and meters credits, the app only mirrors the balance
  (`MemoraCreditMeter`) and reports 402 as `outOfCredits`. The server is not
  built: until it is, the app says the service is not connected. Never put a
  provider key in the app for it.
- Workspaces follow a personal / business split: the personal workspace stays
  on the device (the SQLite store); a team workspace keeps its records in the
  cloud for every member to see and edit. The switcher is at the top of the
  side menu (`WorkspaceSwitcher`, `MemoraModel+Workspace`). The cloud is
  reached only through `TeamBackend`; until Firebase is connected
  `UnconfiguredTeamBackend` refuses team creation and joining with a reason.
  Creating a team needs the team plan; joining with an invite code does not.
- Team sharing publishes a project or a single record to CloudKit
  (`CloudSharingService`) and lists what teammates share back, for both units.
  It needs the iCloud capability and a container matching the bundle identifier;
  without them, or without an iCloud account, the app says so instead of
  pretending. Teammates' records appear on Files under チームから共有 and their
  projects in the side menu's チームから共有 section, each marked with the
  owner's name (`SharedOwnerBadge`) and opened read-only (`SharedRecordView`,
  `SharedProjectView`). Shared items are only read in the background once
  CloudKit has answered on this device (`refreshIfConfirmed`), since touching
  an unconfigured container stops the app. Shared items are read-only snapshots on the receiver: merging into
  the local editable store, member management, media (audio/photo) sync, and
  conflict handling are not built. A manual package export
  (`makeTeamSharePackage`) also remains.
- The Ask AI fallback never invents answers; when no engine can run it says so.
- Ask AI is one assistant with no mode switch. New chats show locally prepared
  agent-action suggestions, personalized only from real cloud-permitted personal
  records/tasks and never from sample content. A selection revalidates sources
  and stages an editable draft without sending; existing drafts/attachments win.
  Keep no random greeting, logo or idle glow. `AskAIHeader` is one compact row:
  sidebar / Memora (history and search menu) / new chat. Replies remain plain
  text with no bubble, only the person's messages in `aiBubble`. `AskAIGlow`
  keeps its processing mesh only while an answer is being formed, still under
  Reduce Motion. Tab navigation and system Ask AI links preserve the conversation;
  only the explicit new-chat action clears it. A bounded SQLite resume document
  (`AIConversationSnapshot`, `MemoraModel+Conversation`) restores settled messages
  and delivered resident posts per workspace. Interrupted operations never resume
  automatically, and UI write grants are never restored. Exchange history remains
  separate. Routing is the app's, not the
  person's (`shouldRunAsAgent`): a cloud model always runs as the agent and is
  given the records found for the request up front; the on-device model, which
  is unreliable with tools, gets the agent only for requests to do something
  and otherwise answers through the grounded path (`sendGroundedAnswer`). The agent
  (`MemoraModel+Agent`, tools in `MemoraModel+AgentTools`, `AgentTool`) runs
  on the chosen cloud model through `CloudAgentSession` (Anthropic tool use or
  OpenAI-compatible function calling), or with no key on Apple's on-device
  model through `OnDeviceAgentTool` (schemas built from the same `AgentTool`
  definitions, a smaller tool set in `AgentTool.onDeviceTools`, and compact
  tool results). Its focus is the work after a meeting: follow-up email drafts
  (`MailDraftSheet`; Mail's composer, or the share sheet without a Mail
  account — it never sends), calendar events (`CalendarService.addEvent`),
  Notion pages, tasks and documents. Reading tools run straight away; every
  tool that changes data waits for the approval card, and a declined change is
  reported back to the model.
- While a reply is being formed, `ThinkingTraceView` shows one live status line
  (考えています / 記録を探しています / 回答を書いています / 作業しています /
  確認を待っています) with elapsed time. Actual `agentSteps` are available in a
  compact disclosure, retained after completion; ordinary answers need no fake
  steps. Show recorded tool events/results only, never private `reasoning` or an
  invented count/progress stage. Ask AI 2.0 follows `docs/ASK_AI_2_IMPLEMENTATION.md`.
- The same rule (only what really happened) governs the other AI pieces:
  `WorkingStatus`/`PixelLoader` time long processing from its real start
  (`ProcessingService.startedAt`); answers cite
  records as 【資料n】 and only numbers matching a sent source become links
  (`AnswerCitations`); follow-ups are built from decisions, tasks and open
  questions the cited records hold (`followUps(for:)`); the agent asks the
  person through `ask_user` (`AgentQuestionCard`) only when the records cannot
  tell it; a project is suggested for an unfiled record only from
  evidence — calendar series, meeting name, shared people
  (`projectSuggestions(for:)`, `ProjectSuggestionCard`).
- Personal memory: Ask AI keeps what the person told it (「〇〇を覚えておいて」,
  Settings › AIと要約 › メモリ, or the agent's `save_memory` after approval) in
  `aiMemories`, and sends it with every question together with related past
  exchanges from `aiHistory` (`personalContext`, `MemoraModel+Memory`). Nothing
  is inferred into memory. A history entry can be continued.
- Ask AI's `@` menu uses the existing registry, service catalog and skills
  (`docs/ASK_AI_PLUGINS.md`). Keep its native TextField, cursor/IME protections,
  SQLite draft IDs and tool restrictions. Ordinary questions retain automatic
  tool selection. Unknown-cost external reads, including Gmail, need approval;
  automatic jobs cannot fetch Gmail until their costs are established. Keep MCP
  endpoint, fingerprint, account, permission and cost checks at execution time.
- Gmail is connected read-only (`GmailService`, OAuth with PKCE, refresh token
  in the keychain) and read by the agent through `search_email` / `read_email`,
  offered only while connected. The build needs a Google iOS OAuth client ID
  under the Info.plist key `MemoraGoogleClientID`; without it the settings
  screen says so.
- CalendarPreview binds only transient UUIDs returned by read_calendar to actual
  EventKit event fields. Cloud calendar reads require the approval card before
  fetching; a declined read cannot be requested again in the same reply.
  `CalendarAgentReadContext` binds approval and fetch to the live request,
  workspace generation, thinking message, policy and calendar revision. An
  integration OFF/ON transition invalidates the revision synchronously; it does
  not revive an old read. Old callbacks never settle a replacement's trace.
  EventKit changes and app activation invalidate these grants, including before
  cloud requests and artifact creation. Never restore calendar grants from history
  or replace source dates/titles with model-supplied values. See
  `docs/ASK_AI_CALENDAR_PREVIEW.md` for mock and real-device validation boundaries.
- Business meetings: a glossary (Settings › 録音と文字起こし › 文字起こし › 用語集,
  `glossaryTerms`) plus the people and project names (`transcriptionVocabulary`)
  is given to every transcription engine (the glossary can be filled from
  recent Gmail — names written to, company names, recurring product names —
  picked out on the device by `GlossaryCandidateExtractor`, never sent to an
  AI, and added only after the person confirms) (SpeechAnalyzer `AnalysisContext`,
  Whisper `prompt`, Deepgram `keywords`) and to the summary prompt. Tapping an
  upcoming event shows 前回から (`meetingBrief`, `MeetingBriefSection`): what
  earlier records of the same calendar series, or the same title once dates and
  numbers are set aside, left open. A recording started from a recurring event
  is filed into the project its last occurrence of the same calendar series is
  in (`recurringProjectID`); a title that only looks alike is never used for
  filing.
- Calls are hidden for now (`FeatureFlags.isCallingEnabled = false`): the
  next step is calling between Memora users inside the app (WebRTC with
  Firebase signalling, PushKit/CallKit, a free-tier TURN relay), not a phone
  line. When enabled, the ＋ menu's 電話をかける sets up calling the first time
  (`CallSetupFlow`: intro, consent notice, own number, verification call,
  contacts) and then opens `DialerView`. A call is carried by a calling
  provider (Twilio Voice or similar) through `CallingService`, because iOS
  does not let apps record ordinary calls; the audio passes through the app and
  is transcribed on the device as a 通話 record (`MeetingSource.call`,
  `saveEndedCall`). Until a provider and its token server are connected,
  `UnconfiguredCallingService` refuses with a reason. The screens can be
  previewed from Settings › 診断とプレビュー › 状態と復旧UIを確認.
- People: the side menu's 人物 (`PeopleView`, `PersonDetailView`) shows what
  the records hold about someone (`MemoraModel.memory(of:)`): meetings they
  were tagged on or spoke in under their name, open tasks assigned to them,
  shared decisions, journal mentions. The agent reads it with `read_person`.
- Weekly reviews: `WeeklyReviewBuilder` writes last week's review from the
  records alone (no model) the first time the app opens in a new week
  (`prepareWeeklyReviewIfNeeded`), stored as a `MemoraDocument` with
  `weekStart`. An unopened one is pointed out on the Journal
  (`WeeklyReviewCard`); 資料 can write this week's on demand.
  Documents (`MemoraDocument`, stored under `memoraDocuments` and in backups)
  are listed from the side menu's 資料 and export as PDF (`DocumentPDF`),
  PowerPoint (`PPTXWriter`, stored ZIP via `ZipArchive`) or text. The agent
  can receive bounded, locally prepared attachment excerpts on the global
  BYOK tool-calling path. Attachment content never grants permissions; writes
  still require approval. Project and record agents remain read-only. Slide
  speaker notes are written into standard .pptx notes parts, once on the first
  derived page of each logical slide. SlidePageLayout supplies the same derived
  pages to screen, PDF and standard PowerPoint without changing saved slides.
  Company-template artifacts retain their original formatting.
- Readability: summaries, Ask AI answers and the agent write to
  `ReadabilityGuide` (rules adapted from yomiyasu and k16shikano's guide,
  credited in `docs/THIRD_PARTY.md`): `rules` for cloud prompts,
  `compactRules` for the on-device window.
- Resident agents (`ResidentAgent`, `ResidentTrigger`, `ResidentAgentCatalog`,
  `MemoraModel+Residents`, Settings › AIと要約 › 常駐エージェント), after OpenDots' Dots
  (design only; its code is TypeScript): named agents that run every morning,
  every Monday, or after a summary is made, and post to the Ask AI
  conversation under their name. BYOK only (`residentLLM`): never Memora
  Intelligence credits or the on-device model. They get only the reading tools
  (`AgentTool.residentTools`, re-checked per call) and write changes as
  「提案:」 lines that become buttons; sending one runs the normal agent with
  approval. Runs come from `BGAppRefreshTask`
  (`app.memora.residents.refresh`, registered in `MemoraAppDelegate`, which
  owns the model) and from returning to the app; iOS picks the background
  time. `lastRunAt` moves only on a finished run, a cut-short run leaves no
  message, and a run missed by more than `lateWindow` is skipped. A
  notification is posted only if already allowed.
- Ask AI defaults to Auto, which follows the configured `AIEngine` and cloud
  selection. A registered model is chosen in Settings › AIと要約 › AIモデル (saved in
  `RegisteredLLMStore`), not from the composer: a menu there dropped the
  keyboard and cancelled the choice. Both Ask AI paths capture
  `askAIConfiguration` once per question. The summary sheet starts on the model
  Ask AI is using (`defaultSummaryEngineChoice`) and can switch to the settings
  engine, the on-device model, or any registered model for that summary.
- Cloud summaries stream (`CloudAIService.completeStreaming`), so a long answer
  is not cut off by an idle timeout, and an answer stopped at the length limit
  is continued. A failed summary on a record with a transcript retries the
  summary, never the transcription.
- Summaries run through `MeetingSummarizer`, not the Ask AI prompt. 詳細な概要
  (`SummaryTemplate.detailedOverview`) is the base template. The cloud writes
  the whole document in one pass (part notes merged when very long); on-device
  reads section by section with guided generation and `SummaryMarkdownBuilder`
  lays the document out. Actions become tasks (existing titles skipped); owners
  and due dates are only set when the meeting said them. Generated summaries
  render with `MarkdownDocumentView`; cards and rows use `summaryPreview`.
  A summary is edited where it is read (`EditableMarkdownDocument`): one block
  or table value at a time, drawn by the same `MarkdownBlockView`, written back
  over only its own lines (`MarkdownBlockWriter`). Do not switch the whole
  summary to its markdown source on tap; the source editor is only offered
  from the long-press menu.
- Summary templates: a marketplace of business templates by category
  (`SummaryTemplateCatalog`, `SummaryTemplateCategory`), each with its own
  `sections`, `focus` and whether it writes an action table; the person can
  write their own as a free prompt (`prompt`, followed instead of sections;
  `SummaryPrompt.promptFormat` only adds the heading and action table the app
  reads back) and keep it in `customTemplates` (record store; older saved
  templates decode with defaults) and choose the
  default 自動生成 uses (`defaultTemplateID`, `defaultSummaryChoice`). Catalog
  ids are kept so templates added in older builds stay added.
- Integrations: webhooks (Settings › 連携 › Webhook, `WebhookEndpoint`,
  `WebhookDelivery`, `MemoraModel+Webhooks`) send every finished summary as
  JSON or a Slack message to https URLs kept in the keychain. Remote MCP
  servers (`MCPServerConfig`, `MCPClient` over Streamable HTTP,
  `MemoraModel+MCP`) lend their tools to the cloud agent as `mcp_…` tools;
  only tools the server marks `readOnlyHint` run without the approval card.
  The on-device agent does not get MCP tools.
- Icons are Lucide (`Shared/MemoraIcon+Lucide.swift`) behind stored names in
  `MemoraIcon` (`Shared/MemoraIcon.swift`); the exhaustive mapping has no
  SF Symbol fallback. SwiftUI, UIKit and widgets share `MemoraIconRendering`.
  Draw them with `Image(icon:size:)`, `Label(_:icon:)`,
  `Button(_:icon:)` and friends rather than a literal `systemName`/`systemImage`,
  so a stored icon resolves the same everywhere. Pass the point size Lucide
  should rasterize at; `.font` does not resize it. Raw values keep the names
  older builds stored. The mapping is listed in `docs/LUCIDE_ICONS.md`.
- Service/account brand identity uses official bundled logos (`AIPluginIcon.brandAssetName`,
  `AIPluginIconView`, `ProviderLogo`) in original colors. See `docs/CONNECTOR_LOGOS.md`.
  Apple's native `apple.logo` is limited to the sign-in button. Device calendar is
  EventKit and must not use Google Calendar branding. Interface glyphs remain Lucide.
- Settings has one entry point: the gear at the bottom right of the side menu
  (`FileSidebarView` footer, beside Memora Plus). Tabs carry no settings button.
  Dark mode is a toggle in Settings › 表示と操作, not in the side menu. The editable
  profile picture remains at the top of Settings. The root has topic links only
  (`SettingsCategory`); switches and service connections live inside each topic.
  Settings and sidebar icons use `MemoraInterfaceIcon`: a 20pt regular Lucide
  outline in a 28pt slot; interactive labels remain at least 44pt. Do not restore colored
  tiles, per-item artwork or separate enlarged search icons.
- Backlog and phase status live in `docs/IMPROVEMENT_BACKLOG.md` and
  `docs/OPENCODE_IMPLEMENTATION.md`.
