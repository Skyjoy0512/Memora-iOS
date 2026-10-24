# Memora — Native reading and conversation

Updated 2026-10-23. This is the current design specification. Product behavior
and access constraints remain in AGENTS.md and domain documents under docs/.
Historical visual experiments are superseded.

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
their system role. No decorative content gradient or manual elevation shadow.

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
when the summary text is folded. Its separate enlarge/share action retains
the accessible full-text alternative and export confirmation. Images are local
excerpts, not a new AI interpretation; edits and access changes invalidate them.
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
pairing/details, PLAUD audio import and generic recorder/voice-memo audio import.
File import is explicitly distinct from Bluetooth pairing and uses the existing
workspace-bound, validated audio/SQLite path. Other vendor protocols are unsupported.

Tools: the side menu's `ToolsView` is a Plaud-style hub for skills, summary
templates and connectors. A top segmented picker switches between マイスキル,
テンプレート and コネクタ, retaining the selection. Plain native lists group
skills by source, templates by category, and connectors by purpose. Article-style
details use a common reading width and a bottom primary action. Skill use stages
a mention in the existing Ask AI draft without sending it; template use sets the
existing automatic-summary preference. The top-right plus opens the same editors
as Settings and preserves Markdown import and MCP registration. Service state
comes from the existing catalog; no fabricated connections or authors.
Service identities use the unmodified official logos through `AIPluginIcon`;
sources are recorded in `docs/CONNECTOR_LOGOS.md`. Ordinary interface controls
continue to use Lucide. The device calendar retains its native calendar glyph.
Connector details use an article layout: official identity and real state,
summary, access/cost explanation, then enable/setup controls. Explanatory
paragraphs are not separate table rows; dividers separate controls only.

The composer plus is an unadorned 44pt target. Its system Menu owns anchored
Liquid Glass opening/closing, without a custom popover, navigation zoom, matched
transition namespace or fixed dismissal delay. Mention candidates occupy layout space above the native input,
so the complete candidate surface is inside its hit-test bounds. The field stays
mounted for cursor/IME continuity, and candidate controls use the shared glass.
The composer occupies 94.5% of the available width, capped at the reading width.
Tools is a full-page destination with a sidebar button, not a bottom sheet.
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
Tools) first, then collections (Projects / Documents / People), Devices, and
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
The supplied 132×27 vector brand mark sits above Library, aligned with the row
icons. Its original light and dark artwork is selected by the asset catalog;
do not tint or redraw the geometry.
At accessibility sizes, secondary row values move below the title rather than
competing for a narrow horizontal column.

## Interaction and accessibility

Liquid Glass belongs to navigation, the side menu, the top-right create control
and the composer. There are no bottom tabs. Keep the composer on the bottom edge.
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
text wraps/reflows; section tabs scroll. Use leading/trailing layout. Native
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
