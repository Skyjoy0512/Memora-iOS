# Memora — Native reading and conversation

Updated 2026-10-20. This is the current design specification. Product behavior
and access constraints remain in AGENTS.md and domain documents under docs/.
Historical visual experiments are superseded.

## Direction and provenance

Put reading, finding and acting on recorded knowledge first: neutral surfaces,
system typography, predictable spacing and familiar native controls. Replies are
documents on the page; only the person's messages have bubbles. Empty Ask AI is blank.

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
| MemoraIconButton | 20pt SF glyph with an actual 44pt accessible/tappable label, not outer spacing |
| ToolbarSearchField | Native focused search; 44pt clear/cancel controls; vertical layout at accessibility text sizes |
| ToolbarIconButton / ToolbarActionLabel | native toolbar labels and accessible actions |
| MemoraInterfaceIcon / MemoraIconMetrics | common menu/settings glyph, alignment slot and touch metric |
| SettingsLabel / SettingsValue / MemoraSettingsPage | wrapping row title, secondary value and shared native grouped page |
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
| ComposerActionMenu | keyboard-preserving attachment actions on the same bounded neutral menu surface |
| AIReplyActionsRow | common response controls and a real excerpt count; vertical at accessibility sizes |
| SidebarAccountFooter | anchored account/plan/settings controls, separated from scrollable destinations |
| Native Form / Menu / sheet / alert | settings, integrations, skill setup, editors and confirmation |

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

Journal: primary ScrollView, flat week selector, minimal timeline glyphs and
hairlines. Neutral recap; expanded summary follows appearance and uses sections,
not nested translucent cards. The selected scenic image remains a small header
and the background-change action remains. Dates, health privacy, source links
and event editing keep their behavior.
The month/year and a real “今日に戻る” action establish date context. Tasks, recent
projects and the empty day are flat sections; the daily recap alone earns a
content group and explicitly says it opens the daily summary.

Library: Files/Projects, sort/filter, selection/share/move/delete and gallery mode
remain. Titles lead, then kind/date/status and optional preview. Gallery groups
use 16pt neutral contours. Search and selection own the bottom edge when active.
Empty-query search shows its scope instead of the list behind it. Search counts
include matching saved sources as well as records. Retry actions clear the same
query binding, not a display-only copy.

Workspace: Chat / Files / Sources in that order, shared flat tabs, rows, empty
states and toolbar actions. Scoped Ask AI reads active-project evidence only;
privacy and membership are checked at execution and completion.
Empty tabs scroll so the action remains reachable with larger text. Tasks,
People and Documents use the same empty-state component, with real add/open
actions. Document and project rows use neutral interface glyphs rather than
decorative tiles; metadata wraps instead of disappearing.

Record detail: common reading width/type for summary, transcript, decisions,
tasks and notes. Flat section tabs. Edit one block/cell in place; Markdown source
editing stays a deliberate context-menu action. Tables retain every value.
Audio, timestamps, source navigation and saving retain their existing paths.
The record header uses its display-title fallback and one wrapping metadata line.

Settings/sheets: native grouped Form, neutral glyphs, system presentation and
common action hierarchy. The root is profile editing plus 11 topic links in four
groups: account, app, data and other. Individual switches, AI models, service
connections, storage and diagnostics live inside the relevant topic. Keep
promotional plan cards out of this index; plan and credit operations remain in
their category. Services have one canonical list under Integrations; skills
belong under AI and summaries. Preserve profile editing, permission explanations,
connection setup and the single sidebar settings entry. No fabricated service state.

Tools: the side menu's `ToolsView` is a Plaud-style hub for skills, summary
templates and connectors. It uses native grouped rows, reports real counts, and
opens the same registration editors as Settings. Creation stays reachable from
the hub; no fabricated connector or skill state.

Sidebar: workspace switcher; the main destinations (Home / Library / Ask AI /
Tools) first, then collections (Projects / Documents / People), Devices, and
plan/settings controls. There is no bottom tab bar. A destination name stays constant; connection
state is a separate secondary value. Rows use the shared 28pt icon column and
52pt minimum height, growing with text. The workspace switcher is the first
scrollable item, without a nested card. Account information and the plan/settings
actions are anchored below the destinations. They wrap without truncation; the
profile avatar is a separate 32pt content role, not an interface glyph. At
accessibility sizes the plan action reads “プラン” and the guest's secondary label
reads “サインイン”; storage context remains in the workspace switcher above. The
spoken plan name still identifies Memora Plus. The settings gear stays at the
bottom right, with its entire 44pt glass circle inside the tappable label.
The drawer uses secondaryBackground, subtly separated from the conversation canvas.
At accessibility sizes, secondary row values move below the title rather than
competing for a narrow horizontal column.

## Interaction and accessibility

Liquid Glass belongs to navigation, the side menu, the top-right create control
and the composer. There are no bottom tabs. Keep the create popover compact and
the composer on the bottom edge.
Create-menu actions explain their input method beneath a stable action name.
The native popover sizes to measured content, caps its ideal height and scrolls;
the recording/import/project destination callbacks are unchanged.
Purposeful spring motion remains; Reduce Motion suppresses nonessential movement.
Loading reflects real operations; never invent progress or expose private reasoning.

Icon-only controls have accessible names. State uses text/traits/symbols as well
as color. Targets are at least 44pt, with background inside the label. Larger
text wraps/reflows; section tabs scroll. Use leading/trailing layout. Native
cursor, selection, VoiceOver and Japanese marked-text composition take priority.

## Verification

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
