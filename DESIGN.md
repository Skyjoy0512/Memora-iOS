# Memora — Native reading and conversation

Updated 2026-11-14. This is the current design specification. Product behavior
and access constraints remain in AGENTS.md and domain documents under docs/.
Historical visual experiments are superseded.

2026-10-27: onboarding offers recording, the non-destructive sample and local
use from the first page; explanatory pages are optional. Auth providers carry
an unavailable label until connected. Plans use native Form/Picker, separating
future pricing/credits from current on-device/BYOK features and local settings.
Brand assets follow the supplied canonical artwork in docs/BRANDING.md. Floating Ask AI controls use native Liquid Glass; motion follows the restrained page/text treatment below. See docs/UI_UX_2026_10.md.

## Everyday interactions

- The sidebar follows the supplied sparse drawer reference: canonical wordmark
  and circular search at the top, Library / Journal / Ask AI / Marketplace in
  regular-weight rows, and a circular settings button at the bottom right.
  The wordmark opens a native menu for projects, documents, people, the recorder,
  account and plan actions. Keep the main drawer free of section headings,
  selection fills, account cards and upgrade copy. Selected destinations remain
  exposed to accessibility, and navigation rows grow and scroll with larger text.

- The bottom idle row holds Ask AI and one plus control in native Liquid Glass.
  Plus opens CaptureMenuSheet with recording, audio import, online meeting and
  note creation, in that order. It has no shortcut strip or close-button header;
  use the native sheet grabber/dismissal. The compact sheet is 300pt at standard text sizes.
  There is no separate memo button or top-right create control. Project creation
  stays in Projects' options menu and empty state.
- AI questions advance only after 次へ/送信. All question controls have at least
  44pt targets and the footer stacks at accessibility text sizes.
- Read-only answer components are included in copy/share/saved documents. Referenced
  tasks, events and other cards resolve through current grants at the action;
  display JSON never supplies their titles, dates or permissions.
- Files (ファイル) and Projects (プロジェクト) switch through the existing pill tabs beneath the Library title.
  Display, sort, filter and selection remain in the adjacent native menu. Library
  sources continue in the lazy list without a three-item preview or a See All link.
- Multiple selection preserves row identity and text width. Change selection,
  headers and composer visibility together without animating List row heights.
  Share, team, move and delete use a floating glass capsule, with two columns
  at accessibility text sizes.
- A project's title menu switches between chat, records and reference sources.
  Its options menu retains project-scoped new chat; capture uses the shared
  bottom row and the visible project. A paperclip denotes source-only attachment actions.
- Keep the Ask AI composer compact, using untinted regular Liquid Glass without
  an opaque card backing or a simulated border. Normal ready states need no badges;
  partial content, failures and recovery actions stay visible. Source metadata
  forms one quiet line; summary, original and source links retain their roles.
- New Ask AI chats show quiet prompt suggestions without a marketing heading,
  repeated generic subtitles or a permanent explanation beneath them. Preserve
  source titles, draft protection and approval at execution time.
- Marketplace follows the supplied catalog reference: a compact title picker,
  active-item icon strip, and spacious icon/title/description rows with separate
  add and options controls. Search stays in a floating capsule at the bottom,
  with global or category scope. Detail screens use a left-aligned icon and title,
  expandable description, information rows, top share action and bottom primary
  action. Provider logos retain their original colors. Use real availability and
  connection state; do not invent popularity, developer names or versions.
- Show the content and the next useful action first. Avoid repeating titles,
  describing gestures in paragraphs, or showing empty insight groups.
- Use short action labels: 録音する, 音声を取り込む, 要約する. Use 記録 for
  recordings/transcripts, 参考資料 for imported context, and 連携 for services.
  Stored navigation and setting identifiers keep their existing values.
- Summary setup shows AI, format and length. Put use case and processing policy
  in 詳細設定. Native pickers own selection and navigation.
- Keep the actual cloud destination beside the explicit send action. Show errors
  next to the failed control, with an action to resolve them. Generic assurances,
  implementation details and repeated warnings do not belong in the main flow.
- Connect and manage services through controls first. Connection status is visible;
  technical access details expand only when requested.

## Cross-screen reading review — 2026-11-13

Collection rows anchor icons and actions near the title. At accessibility sizes,
documents, reference sources, projects, marketplace items and people place their
artwork above the text so long Japanese labels can use the available width.
Document rows follow the same title / metadata / preview order as Library records.
When a Library row stacks its source icon, its badges and preview also align with
the title instead of retaining an empty icon-column indent. Selection keeps its
stable row identity and never animates wrapped heights.

Keep the Marketplace active-count tile intrinsically sized; counts must not turn
into an ellipsis at large text sizes. Show three leading icons at accessibility
sizes, five otherwise, and count the remaining items correctly. Journal insertion
capsules grow vertically
with their labels while preserving their native menu and at least 44pt targets.
Search fields shorten the visible prompt to 検索 at accessibility sizes, while
their accessibility labels retain the full search scope. Contextual Ask AI fields
use この記録に質問 / このプロジェクトに質問 (質問する at accessibility sizes), with the
actual record or project name in the field's accessibility hint. Neither the
question scope nor the draft changes. Sample notices stay secondary and their
short 削除 action keeps its full spoken label and confirmation dialog.

Review coverage and validation are recorded in
[UI/UX review](docs/UI_UX_REVIEW_2026_11_13.md).

## Capture and Library refinements — 2026-11-14

The attachment menu sits outside the composer's glass foreground so native menu
presentation keeps the input capsule visible. The editor, draft and attachment
pickers retain their identity. The separate capture sheet contains only its four
main actions, with native drag dismissal.

Upcoming events show only the day number in the left tile; the full date and time
remain beside the title. Library rows hide source glyphs while reserving the same
space for selection marks, preserving wrapped title widths during selection.
PLAUD shares the other-recorder/voice-memo import route. The recorder hub omits its
long explanatory footer; import-specific instructions remain on the import screen.
The Omi search button centers its text and provides at least a 44pt touch target.

## Direction and provenance

Put reading, finding and acting on recorded knowledge first: neutral surfaces,
system typography, predictable spacing and familiar native controls. Replies are
documents on the page; only the person's messages have bubbles. New Ask AI chats
show quiet action suggestions above the composer, without an idle logo or glow.

Official sources consulted:
[Apps SDK UI](https://github.com/openai/apps-sdk-ui),
[UI guidelines](https://developers.openai.com/plugins/concepts/ui-guidelines),
[primitive tokens](https://github.com/openai/apps-sdk-ui/blob/0f00143c7a639906f1621fe58e1b6be7b5bea46d/src/styles/variables-primitive.css),
[semantic tokens](https://github.com/openai/apps-sdk-ui/blob/0f00143c7a639906f1621fe58e1b6be7b5bea46d/src/styles/variables-semantic.css).
See [source analysis](docs/design-refresh/PLAN.md). These are web tokens, not
unpublished ChatGPT iOS measurements. The native sizes, reading width, springs
and Japanese text rhythm below are Memora decisions. No React or WebView is used.

Apple foundations: [Typography](https://developer.apple.com/design/human-interface-guidelines/typography),
[Materials](https://developer.apple.com/design/human-interface-guidelines/materials),
[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility).

## Design tokens

Single implementation: MemoraPalette, MemoraTypography, MemoraSpacing,
MemoraRadius and MemoraMotion in App/. Native Form, List, Menu, toolbar, sheet
and alert retain system sizing and focus behavior.

| Color role | Light | Dark | Use |
|---|---|---|---|
| background | FFFFFF | 212121 | reading/chat canvas |
| secondaryBackground | F9F9F9 | 181818 | inset content/code |
| card / elevated | F3F3F3 / FFFFFF | 303030 | content groups / candidate menu |
| textPrimary / action | 0D0D0D | FFFFFF | primary text and solid actions |
| textSecondary | 5D5D5D | AFAFAF | supporting text and metadata |
| actionLabel | FFFFFF | 0D0D0D | text on solid action |
| selection | EDEDED | 414141 | selected tab/row/field |
| border | E5E5E5 | 353535 | subtle separators |
| focus | 0169CC | 339CFF | native focus/link semantics |
| danger | BA2623 | FF8583 | errors with explanatory text |
| warning | 923B0F | FF9E6C | warnings with symbol and text |
| success | 00692A | 66D492 | verified completion |

Supporting text and borders strengthen in Increase Contrast. Essential
explanations are never disabled text. Provider logos, calendar categories,
profile images and photos keep their content colors. Destructive actions retain
their system role. No decorative content gradient or manual elevation shadow in reading or settings surfaces. Marketplace catalog artwork may use category gradients; labels stay on semantic surfaces.

| Type role | Native style | Default iOS size / weight |
|---|---|---|
| Display | largeTitle | 34 / semibold |
| Screen Title | title | 28 / semibold |
| Section Heading | title3 | 20 / semibold |
| Body | body | 17 / regular |
| Reading Body | body | 17 / regular |
| Secondary | subheadline | 15 / regular |
| Caption | caption | 12 / regular |
| Metadata | footnote | 13 / regular |

Every role follows Dynamic Type. SF uses the native Japanese fallback. Reading
adds 6pt scaled line spacing and natural tracking. Paragraphs are 16pt apart.
Major headings have 16pt additional space above; minor headings 8pt. Bullets use
a scaled 20pt marker column and hanging indentation; deep nesting is bounded on
narrow screens. Reading and UIKit attributed editing share fonts and leading.
Chat/document columns cap at 680pt. Interface glyphs keep a consistent optical
size while their labels follow Dynamic Type; avatars and content artwork are
separate roles.

| Spacing token | pt | Role |
|---|---|---|
| xxs / xs / sm | 2 / 4 / 8 | fine alignment / related labels |
| md / lg / xl / xxl | 12 / 16 / 20 / 24 | rows / padding / inset / groups |
| section / group / page | 32 / 40 / 48 | sections / larger groups / page rhythm |
| screen / card / row | 20 / 16 / 12 | semantic aliases |
| touchTarget | 44 minimum | controls grow with larger text |
| messageWidth | 420 maximum | concise empty/search explanations |
| readingWidth | 680 maximum | long-form content |

Radius: small 8, field 12, card 16, bubble/composer 24pt; actions are capsules.
System sheets/menus own their contours. Group related content sparingly.

Interface icon tokens (`MemoraIconMetrics`): 20pt regular Lucide outline, 28pt
alignment slot in menu/settings rows, at least 44pt actual control label.
Custom disclosure accessories use the separate 12pt accessory role.
`MemoraInterfaceIcon` normalizes paired filled symbols to their existing outline
variant for navigation only; stored `MemoraIcon` values never change. Toolbars,
search and speech controls use the same glyph size. Native system menus own
their symbol layout. Profile avatars are 48pt in navigation, not menu glyphs.
SwiftUI, UIKit editing controls and widgets share `MemoraIconRendering`: a
2/24 proportional stroke on Lucide paths, rendered at an explicit point size.
There is no SF Symbol fallback. `.font` and SF-specific symbol effects do not
resize or animate these template images; use explicit sizes and opacity
transitions. Keep the 15-second transport label visible on rotation glyphs.
Do not reintroduce per-item artwork, scale multipliers or oversized search icons.

## Shared components

| Component | Responsibility |
|---|---|
| MemoraButtonStyle | solid primary / neutral secondary actions, pressed and disabled states |
| MemoraIconButton | explicit 20pt Lucide glyph with an actual 44pt accessible/tappable label, not outer spacing |
| MemoraQuietButtonStyle | brief opacity feedback without another background or decorative movement |
| memoraReadingText | prose uses the same body size and 6pt extra leading as Markdown |
| ToolbarSearchField | Native focused search; 44pt clear/cancel controls; vertical layout at accessibility text sizes |
| ToolbarIconButton / ToolbarActionLabel | native toolbar labels and accessible actions |
| MemoraInterfaceIcon / MemoraIconMetrics | common menu/settings glyph, alignment slot and touch metric |
| SettingsLabel / SettingsValue / MemoraSettingsPage | wrapping row title, secondary value and shared flat page |
| MemoraList / MemoraForm / memoraPlainList | collections, selectors and native editing controls on one flat canvas |
| SettingsCategory / SettingsCategoryView | typed topic navigation; original leaf bindings and permission confirmations |
| AIComposerBar / QuickAIComposer | native input, attachments, speech, submit/stop, scoped selection |
| MemoraTextTabBar / MemoraSectionPicker | flat scrollable content tabs and selection traits |
| ProminentTabBar | protected UISegmentedControl navigation and system selection morph |
| ProjectRecordRow / ProjectSourceRow / ProjectDocumentRow | common Library/workspace title and metadata hierarchy |
| MemoraSectionHeading | shared section title and supporting context; stacked at accessibility sizes |
| MemoraActionLabel / MemoraMenuButtonStyle | explanatory action rows, common glyph and pressed feedback |
| memoraCard / MemoraIconBadge | restrained grouping and content glyphs |
| MemoraEmptyState | shared empty/search/filter explanation and an optional real recovery action |
| MemoraLoadingContainer / MemoraSkeleton / WorkingStatus | real loading, static skeleton, cancellation, recovery, elapsed time |
| MarkdownBlockView / MarkdownTableRow | common prose, heading, list, quote and stacked table values |
| AIResponseMarkdownBlock / StreamingMarkdownView | same type, incremental rendering, code copy, comparison tables |
| EditableMarkdownDocument / InlineMarkdownEditor | in-place block/cell edit and durable drafts |
| AIPluginMenu / ComposerMentionStrip | common @/+ candidates and removable selections |
| AIPluginMenuRow / AIPluginMenuCopy | succinct display-only builtin explanations; separate availability/cost, selected and pressed feedback |
| Composer attachment Menu | native anchored attachment actions; mention selection preserves the native input |
| AIReplyActionsRow | common response controls and a real excerpt count; vertical at accessibility sizes |
| SidebarAccountFooter | anchored account/plan/settings controls, separated from scrollable destinations |
| MemoraForm / native Menu / sheet / alert | settings, integrations, skill setup, editors and confirmation |

Standard presentation pages use SlidePageLayout for line breaks, fixed 24pt
body type and content-preserving pagination across screen, PDF and PowerPoint.
DocumentSlidesView keeps the white 16:9 page flat, with a separate page count,
native text disclosure and speaker-note disclosure. At accessibility text sizes,
the readable text replaces the scaled page. Saved logical slides remain intact.
Company template artifacts keep their original file and formatting.

GlassSegmentedPicker/Control and arbitrary memoraCard(radius:) are retired.
The old colored SettingsIconStyle tiles and per-section Tint palette are retired;
settings and integration screens share one monochrome glyph implementation.

## Screen composition

Ask AI: compact sidebar/history/new-chat header; no idle decoration. A 32pt
message rhythm and selectable Markdown on the canvas. Keep stable TextField
identity, native composer Glass and 44pt controls. Candidates appear above the
composer and respect keyboard height.
The header is flat, with the title beside the sidebar icon and a visible menu
chevron. On the Ask AI tab, the composer stays two-row and keeps its width when
focus changes; only contextual prompts use the compact capsule. Idle voice input
is an outline glyph; send, stop and active voice states earn the inverse circle.
Active focus/listening belongs to the composer; a saved draft alone neither focuses
the field nor opens the keyboard. After dismissing the keyboard, a draft can remain
while the side menu becomes available.
Response controls share the 20pt interface glyph; source disclosure has a 44pt
target and moves below the actions at accessibility sizes.
New chats show three flat agent-action suggestions: tasks, follow-up mail and
documents, with an unfinished-task suggestion when an eligible task exists.
Titles come only from real, cloud-permitted personal records/tasks, never sample
content or inferred memory. Without eligible evidence the labels describe generic
starting actions, not personalized results. Selection revalidates the source and
stages an editable draft; it does not send, call a model or approve a tool. An
existing draft/attachment disables the suggestions rather than replacing input.

Journal: primary ScrollView, flat week selector, minimal timeline glyphs and
hairlines. Neutral recap; expanded summary follows appearance and uses sections,
not nested translucent cards. The selected scenic image remains a small header
and the background-change action remains. Dates, health privacy, source links
and event editing keep their behavior.
The month/year and a real “今日に戻る” action establish date context. Tasks, recent
projects and the empty day are flat sections; the daily recap alone earns a
content group and explicitly says it opens the daily summary.

Library is the opening screen. Files/Projects, sort/filter, selection/share/move/delete and gallery mode
remain. Titles lead, then kind/date/status and optional preview. Gallery groups
use 16pt neutral contours. Search and selection own the bottom edge when active.
Empty-query search shows its scope instead of the list behind it. Search counts
include matching saved sources as well as records. Retry actions clear the same
query binding, not a display-only copy.

Workspace: Chat / Files / Sources in that order, shared flat tabs, rows, empty
states and toolbar actions. Scoped Ask AI reads active-project evidence only;
privacy and membership are checked at execution and completion.
Source status describes extraction, not permission: 本文解析済み / 一部解析済み /
本文抽出済み · 解析範囲未確認. YouTube title-only results say メタデータのみ;
they do not imply access to audio, subtitles or the complete video. External-AI
permission remains separate. Source memo editors retain both title and body drafts
after failed saves and reopening; failures do not dismiss the editor.
Empty tabs scroll so the action remains reachable with larger text. Tasks,
People and Documents use the same empty-state component, with real add/open
actions. Document and project rows use neutral interface glyphs rather than
decorative tiles; metadata wraps instead of disappearing.
People and Documents open the shared toolbar search rather than a persistent
search drawer. An empty query explains its scope without showing the underlying
list. People match names and notes; documents match locally stored titles,
Markdown, slide text and project names. No file download or external search is
implied. Document rows show a short two-line preview; the toolbar keeps search
and one menu for weekly review, mail drafts and company templates.
The document source editor confirms meaningful unsaved changes, provides a
keyboard Done action and only dismisses after a successful save. An unchanged
save is disabled so it cannot clear a generated file or change its timestamp.
Tasks share the flat list's row margins. Active filters have a short visible
summary and one clear action; empty results retain their existing reset action.
Task progress and planned work dates appear as secondary text only when present,
separate from the due date. Completed rows stay quiet. The long task editor opens
at the large detent so its fields are not hidden in a short initial sheet.
Project renaming focuses the native field, accepts keyboard Done, prevents an
unchanged save and confirms discarding edits. A failed save keeps the entered
name. Empty mail drafts use the shared empty state and a real Ask AI return
action that preserves the conversation draft; Mail remains the sending surface.

Record detail: common reading width/type for summary, transcript, decisions,
tasks and notes. Flat section tabs. Edit one block/cell in place; Markdown source
editing stays a deliberate context-menu action. Tables retain every value.
Audio, timestamps, source navigation and saving retain their existing paths.
The one-page summary image appears inline above the editable summary, even
when the summary text is folded, without a visible title, caption or action row.
Its long-press menu and VoiceOver actions offer enlarge/share and AI generation,
keeping operation labels off the reading canvas. The enlarge/share sheet retains
the accessible full-text alternative and export confirmation. Images are local
excerpts until the person explicitly generates a separate AI interpretation;
edits and access changes invalidate them. AI diagrams use a prominent takeaway
and content-selected metric/flow/comparison/timeline/note panels, not the original
heading order or fixed summary slots. Each claim retains a verified source quote,
with interpretation and model provenance disclosed; the full-text alternative
exposes every claim and quote. A generator sheet explains cloud transfer and cost,
checks the record's policy or a one-run consent, and never starts on opening.
The explicitly fictional, unedited diagnostics sample has a labeled display-only
diagram. No real record receives sample interpretations. Three contextual questions
at the bottom stage a record-scoped draft only, preserving existing input,
attachments and mentions; normal send-time privacy checks still apply.
The image keeps its reading width but fits its content height, without empty
fixed-height columns or a blank page tail. Fallback excerpts follow the saved
document's own headings, hierarchy, lists and table labels, not fixed decision/action slots.
Long images are fitted by removing whole groups before allocating the PNG;
bounded text and omitted material are disclosed, with the untouched full text available.
The task-add action uses the shared quiet capsule with a 44pt minimum target.
The redundant template section/source
disclosure is not shown; the editable summary, transcript tab and history remain.
Decision lists omit the per-item transcript confirmation/source shortcuts;
editing remains on the item, and the transcript stays in its own section tab.
Nested bullet items use a quiet branch glyph. Explicit reason/condition labels
carry the meaning; nesting alone never asserts causation. Real summaries only
use causal structure supported by their transcript. Display samples are labeled
as fictional, contain no audio and can be added individually from Diagnostics
without replacing existing records.
The record header uses its display-title fallback and one wrapping metadata line.
Summary section headings are text-only, retaining the disclosure chevron and
44pt touch target. The Library's section selector sits 12pt below the toolbar;
its sort control uses the same trailing margin as the create button. Month
headings use the shared Japanese formatter.

Settings/sheets: `MemoraForm` keeps native fields, pickers and switches in a
plain List on the same canvas as Library, Ask AI and Tools. No inset grouped
cards or system-grouped page backgrounds. Sections use text headings, quiet
separators, 20pt row margins and 24pt spacing. The shared `memoraPlainList`
also styles secondary collection pages. Editors retain their existing drafts,
save/cancel actions, bindings and permission confirmations.
The root is profile editing plus 12 topic links in four
groups: account, app, data and other. Individual switches, AI models, service
connections, storage and diagnostics live inside the relevant topic. Keep
promotional plan cards out of this index; plan and credit operations remain in
their category. Services have one canonical list under Integrations; skills
belong under AI and summaries. Preserve profile editing, permission explanations,
connection setup and the single sidebar settings entry. No fabricated service state.
Workspace selection, team creation and joining live under Settings › ワークスペース.
Workspace options are visible rows with one checkmark, not a pull-down menu.
They retain storage descriptions, selected accessibility traits and the existing
workspace switch path. An unconfigured backend does not fabricate team options.
The sidebar's recorder entry opens the same recorder hub as Settings: Omi direct
pairing/details and one audio-import destination for PLAUD, other recorders and voice memos.
File import is explicitly distinct from Bluetooth pairing and uses the existing
workspace-bound, validated audio/SQLite path. Other vendor protocols are unsupported.

Tools: the side menu's `ToolsView` opens the marketplace for skills, summary
templates and connectors. Horizontal card shelves open single-column card catalogs.
Details use a large gradient hero, native sheet toolbar, metadata grid and a
scrolling article at the common reading width. Skill use stages
a mention in the existing Ask AI draft without sending it; template use sets the
existing automatic-summary preference. The top-right plus opens the same editors
as Settings and preserves Markdown import and MCP registration. Service state
comes from the existing catalog; no fabricated connections or authors.
Service entries use official identity images through `AIPluginIcon`; local
calendar and interface actions use Lucide. Logo sources are
recorded in `docs/CONNECTOR_LOGOS.md`. Provider logos and the supplied Memora
brand mark remain identity images, separate from interface glyphs.
Connector details share the marketplace hero, with the service's identity and
connect/manage action, followed by real state, capabilities and enable/setup
controls. Access/cost explanations expand on request.

The composer plus is an unadorned 44pt target. Its system Menu owns anchored
Liquid Glass opening/closing, without a custom popover, navigation zoom, matched
transition namespace or fixed dismissal delay. Mention candidates occupy layout space above the native input,
so the complete candidate surface is inside its hit-test bounds. The field stays
mounted for cursor/IME continuity, and candidate controls use the shared glass.
The composer occupies 94.5% of the available width, capped at the reading width.
Marketplace (the saved Tools destination) is a full-page destination with a sidebar button, not a bottom sheet.
Sidebar selections replace content without a second page-slide animation;
only the drawer closes. Details still use native push/back navigation.
The underlying tab surface stays mounted while Tools is visible, preserving
navigation and conversation state. Its UIKit-backed views sit outside the
viewport and are hidden from interaction while covered by Tools. Settings,
recorder, account and plan sheets
wait for actual drawer-animation completion, not an arbitrary delayed task.
Tools and their details share the canvas background and 44pt circular toolbar
controls, including Menu labels. Tool lists use 16pt section spacing, 12pt/8pt
heading insets and medium-weight titles; summaries use 3pt extra leading.
Management rows share the canvas rather than switching to grouped black cards.
Bottom primary actions use large native Liquid Glass capsules, without adding
another minimum height on top of the native style's padding. Article actions
align with the 20pt content margin and reading-width limit.
The capture menu shows action names and icons in 44pt rows with a 260pt width
that grows with Dynamic Type up to 320pt; explanations remain VoiceOver hints.

Sidebar: the main destinations (Library / Journal / Ask AI /
Marketplace) first, then collections (Projects / Documents / People), Devices, and
plan/settings controls. There is no bottom tab bar. A destination name stays constant; connection
state is a separate secondary value. Rows use the shared 28pt icon column and
52pt minimum height, growing with text. Signed-in account information and the plan/settings
actions are anchored below the destinations. Guest sign-in is not shown; account
setup remains in Settings. They wrap without truncation; the
profile avatar is a separate 32pt content role, not an interface glyph. At
accessibility sizes the plan action reads “プラン”; workspace and storage context live in Settings. The
spoken plan name still identifies Memora Plus. The settings gear stays at the
bottom right, with its entire 44pt glass circle inside the tappable label.
It is the only Settings entry in the drawer; the top group contains destinations
only, not a second copy of the same action.
The drawer uses secondaryBackground, subtly separated from the conversation canvas.
The supplied 410×68 geometric MEMORA wordmark is displayed at 144pt wide
above Library, aligned with the row icons. Its original light and dark artwork is selected by the asset catalog;
do not tint or redraw the geometry.
At accessibility sizes, secondary row values move below the title rather than
competing for a narrow horizontal column.

## Interaction and accessibility

Liquid Glass belongs to navigation, the side menu, the floating capture controls
and the composer. There are no bottom tabs. Keep the shared row on the bottom edge.
Create-menu actions show a stable action name; input explanations are spoken hints.
The create and composer attachment controls delegate presentation to native Menu,
without custom zoom transitions, measured popovers or timed dispatch delays.
Empty-state capture requests reuse the create actions in a native confirmation
dialog. Attachment opening never replaces the input surface.
Native attachment rows preserve all photo, audio, file,
mention and integration actions; no unimplemented camera or new assistant mode is implied.
Memo creation is presented by the root, not the Journal tab, so a create menu
on Library can open it too. Journal supplies its selected day through transient
model state; dismissal clears that date. Capture destinations reuse the existing
model/import paths; the system coordinates menu dismissal and the next sheet.
Only the active destination responds to the
shared capture request. Inactive TabView toolbars must never present alongside it.
Search lives in the side menu and names the current destination. It opens the
existing local search UI without changing the selected screen; Ask AI retains
its conversation search sheet. Root Library and Journal toolbars use the former
search slot for device status and the recorder hub. Only a connected recorder's
valid standard Bluetooth Battery Service value is shown as a percentage;
unavailable values are not invented or substituted with the phone battery.
Record-detail playback/share actions are native ToolbarItemGroup items, available
immediately without staggered timers or manually drawn glass backgrounds.
Tools search uses the same toolbar field as Library and Journal, keeping the
skills/templates/connectors segments in place. It filters local catalog metadata,
not record contents or connected services. Empty results sit above the keyboard
with a short text hint rather than a large decorative icon.
Skill editing explains missing or over-limit fields inline, keeps procedure text
intact and provides a keyboard Done action. Cancel confirms only meaningful
unsaved changes; no confirmation is needed for an unchanged editor.
Purposeful spring motion remains; Reduce Motion suppresses nonessential movement.
Shared timings are 0.32s for screens, 0.30s for the drawer, 0.22s for controls
and 0.14s for press feedback. First-appearance movement is limited to 8pt;
no staggered entrances are added to ordinary lists or reading pages. The drawer
uses a narrow, low-opacity shadow rather than a heavy floating-panel effect.
Loading reflects real operations; never invent progress or expose private reasoning.

Icon-only controls have accessible names. State uses text/traits/symbols as well
as color. Targets are at least 44pt, with background inside the label. Larger
text wraps/reflows; section tabs become a native menu Picker at accessibility sizes. Use leading/trailing layout. Native
cursor, selection, VoiceOver and Japanese marked-text composition take priority.

## Verification

The cross-screen source inventory and its distinction from runtime coverage are
in [UI_SCREEN_AUDIT](docs/UI_SCREEN_AUDIT.md). The sweep includes secondary
lists, editor sheets, account/plan/onboarding, reading pages and presentation
fixtures. Primary actions use action/actionLabel rather than white on adaptive
tint; native toolbar labels use 28pt inside the system's 44pt platter, while
custom glass controls keep their own 44pt label. Media canvases retain native
gestures, and unconnected services continue to say they are unconnected.

[Research and migration plan](docs/design-refresh/PLAN.md),
[before/after review](docs/design-refresh/REVIEW.md), and
[validation results](docs/design-refresh/VALIDATION.md) live under docs/design-refresh/. Tests cover mention
range edits, scoped evidence/tools, persistence, navigation, Markdown and edit
round trips. Compilation is not visual/device proof. Live provider execution,
microphone, CloudKit and hardware require their actual configuration.

[UI polish review](docs/design-refresh/POLISH.md) records the subsequent candidate-menu,
list hierarchy and empty-state refinements without replacing the original audit.
[Settings and icon review](docs/design-refresh/SETTINGS.md) records the topic
hierarchy, relocated controls, icon metrics and follow-up verification.
[Cross-screen experience review](docs/design-refresh/EXPERIENCE.md) records the
subsequent Journal, Library, workspace, task, people, document and capture refinements.
[Chat surface review](docs/design-refresh/CHAT_SURFACE.md) records the later
conversation-first header, stable composer, draft navigation and sidebar refinement.


## 2026-10-31 usability refinements

Collection search uses the same local, whitespace-separated AND matching across
Library, projects, Journal, people, documents and Tools, with case/width/diacritic
folding. An empty or whitespace-only search shows guidance, with the original
collection hidden. Search submission dismisses the keyboard; clearing the field
focuses it again. No-result guidance scrolls and provides a clear-query action.
Marketplace home searches across skills, templates and services, including custom items. Each full catalog searches its own category. See
[coverage and verification](docs/handoffs/UI_UX_POLISH_2026_10.md).

At accessibility text sizes, content selectors use the native menu Picker,
identifying titles wrap fully, metadata reflows, and Library bulk actions use two
columns. While selecting, Library shows selectable local records and the bulk
bar; sample-removal actions, unrelated sources/shared records and normal row
mutation menus step aside. Task text uses a real Button independent of its
completion control. Keep the system back control in pushed screens and standard
push navigation for Library meetings. Edge-swipe behavior still needs physical
device verification; a successful back-button tap is not that evidence.

## Marketplace — 2026-10-31

The sidebar names the destination マーケットプレイス. Its existing Tools state and
root navigation remain intact. The home has one editorial recommendation and
horizontal shelves for skills, summary templates and integrations. Each shelf
opens a vertically scrolling, single-column card catalog with すべて見る; every card opens the existing working
detail view. Search is local catalog metadata only and never queries a service.
There are no fabricated installs, rankings, reviews or public publisher claims.

Artwork is a static Lucide glyph on a category gradient, clipped to its own
thumbnail. Card labels use semantic colors and system type. Accessibility sizes
wrap full labels and expand cards. No autoplay or decorative animation. Native
push/back, search, menu and sheet behavior owns navigation and creation.
The root plus offers skill creation/import, template creation and MCP registration;
each category offers its relevant actions. Management remains reachable from home,
full catalogs and Settings. Existing service status and approval rules are intact.

Full catalogs and cross-category search reuse the same artwork and cards as the
home shelves. Full-width cards wrap their complete title and description. The
column stays single on wider displays, capped at 680pt for reading. Saved templates
appear once under マイテンプレート, rather than repeating in their category. Disabled
skills and the selected default template retain their status. The connector
catalog uses cards; Ask AI's connector hub retains its native connection list.

The bundled catalog has 32 skills and 55 summary templates. Sixteen additional
skills cover preparation, decision history, blockers, risks, requirements, FAQ,
feedback, comparisons, learning, interview questions, indexes, procedures,
handover, estimates, goals and weekly planning. These workflows read permitted
records/tasks and return sourced answers; they do not grant writes or external
reads. Twelve additional templates cover design, incidents, releases, experiments,
partners, onboarding, mentoring, reading groups, workshops, events and family
discussions. Educational and family summaries do not turn suggestions into tasks.

## Community and connectors — 2026-10-31

Community appears directly below the featured marketplace card. Popular/newest
and personal submissions use actual server state, author names and counters; no
fixture fills an unconfigured service. Publishing previews the exact definition
and exposes public-content rules before submission. Personal skill/template
definitions can also be shared locally and reviewed in the existing editors.

Ask AI's plus and marketplace service cards open the same native connector
sheets: actual connected services, recommendations and unavailable services.
Details put identity, connect/manage and human-readable capabilities first;
access details expand on request. Connection and AI-use permission remain
separate. Provider configuration and execution-time approvals stay intact.

## Official service identity — 2026-10-31

External service marks use the bundled official Gmail, Drive, Notion, GitHub and
MCP artwork across connector lists/details, marketplace cards/search, Ask AI
candidates and selected chips. Preserve aspect ratios and original colors;
service marks do not use the tilted artwork treatment. GitHub uses its supplied
light/dark variants. Device calendar keeps the Lucide calendar because it is
EventKit, not a Google Calendar connection. Google sign-in uses the official G
mark; Apple's OS mark appears only for Apple sign-in. Provider logos keep their
original artwork on white plates for legibility. Navigation/action glyphs remain
Lucide. See docs/CONNECTOR_LOGOS.md for provenance.

## Restrained motion — 2026-11-02

Main Library, Journal and Ask AI content, Library destinations and settings forms
fade in briefly on first appearance. Keep navigation chrome, the composer and
scrolling rows stable; do not replay motion on list updates. Source, recording
and generated-document titles and reading bodies use a short line-opacity reveal
with fixed layout, once per mounted reading surface. Editing does not restart it.
Only a new streaming Ask AI reply receives an introduction, once per message;
arriving prose fades over 200ms in fixed arrival ranges of at most eight characters,
bounded to eight ranges and the latest 64 parsed characters. A later token never
changes an earlier range's opacity. Settled prefixes and history stay fully visible.
No per-frame parsing, timers, blur or per-glyph animation. Reduce Motion shows
text immediately and retains only the existing brief page fade.
Marketplace and export renderers keep their existing presentation.

## Split bottom capture controls — 2026-11-02

The latest requested layout supersedes earlier top-right create guidance. The
compact idle Ask AI field omits its voice-input glyph; the independent plus
opens the recording menu. Focusing the field or dictation gives the composer full width; a paused draft
keeps capture available without clearing it. Its expanded controls keep message voice input and sending.
Capture circles are 52pt with 8pt gaps and 12pt outer margins. Keep separate glass
surfaces without a shared container so native menu rows remain tappable. The
controls belong to a fixed trailing overlay, outside the composer's resizing
layout. Remove their visual menus without animation while typing; do not shrink
or fade native glass. Keep the presentation host mounted so a picker's keyboard
cannot remove its importer. Preserve the editor identity as its trailing padding changes.
Search/selection retain the bottom edge. Record, transcript, source, PDF and
generated-document details show only the full-width Ask AI composer; the capture
presentation host stays mounted with its visual plus hidden. Shared received
items also hide creation.
The Ask AI page likewise shows its full-width composer without the capture FAB.
Marketplace keeps its existing presentation.

Library source glyphs are hidden; selection marks use the reserved lane, keeping title width
and wrapped height unchanged. Avoid animating the list for individual selection toggles.
The create-menu memo uses the existing source editor in memo mode: body, optional
title and current Library/project destination. Drafts are separate from link/file
addition; note commit and draft removal are atomic. Journal's dated entries and
existing stored memos are preserved.
