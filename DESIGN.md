# Memora — Native reading and conversation

Updated 2026-10-19. This is the current design specification. Product behavior
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
Chat/document columns cap at 680pt. Fixed glyph sizes represent artwork, not prose.

| Spacing token | pt | Role |
|---|---|---|
| xxs / xs / sm | 2 / 4 / 8 | fine alignment / related labels |
| md / lg / xl / xxl | 12 / 16 / 20 / 24 | rows / padding / inset / groups |
| section / group / page | 32 / 40 / 48 | sections / larger groups / page rhythm |
| screen / card / row | 20 / 16 / 12 | semantic aliases |
| touchTarget | 44 minimum | controls grow with larger text |
| readingWidth | 680 maximum | long-form content |

Radius: small 8, field 12, card 16, bubble/composer 24pt; actions are capsules.
System sheets/menus own their contours. Group related content sparingly.

## Shared components

| Component | Responsibility |
|---|---|
| MemoraButtonStyle | solid primary / neutral secondary actions, pressed and disabled states |
| MemoraIconButton | 20pt SF glyph with an actual 44pt accessible/tappable label, not outer spacing |
| ToolbarIconButton / ToolbarActionLabel | native toolbar labels and accessible actions |
| AIComposerBar / QuickAIComposer | native input, attachments, speech, submit/stop, scoped selection |
| ToolbarSearchField | contextual native search and IME/cursor behavior |
| MemoraTextTabBar / MemoraSectionPicker | flat scrollable content tabs and selection traits |
| ProminentTabBar | protected UISegmentedControl navigation and system selection morph |
| ProjectRecordRow / ProjectSourceRow / ProjectDocumentRow | common Library/workspace title and metadata hierarchy |
| memoraCard / MemoraIconBadge | restrained grouping and content glyphs |
| ProjectWorkspaceEmptyState | shared empty explanation and useful next action |
| MemoraLoadingContainer / MemoraSkeleton / WorkingStatus | real loading, static skeleton, cancellation, recovery, elapsed time |
| MarkdownBlockView / MarkdownTableRow | common prose, heading, list, quote and stacked table values |
| AIResponseMarkdownBlock / StreamingMarkdownView | same type, incremental rendering, code copy, comparison tables |
| EditableMarkdownDocument / InlineMarkdownEditor | in-place block/cell edit and durable drafts |
| AIPluginMenu / ComposerMentionStrip | common @/+ candidates and removable selections |
| ComposerActionMenu | keyboard-preserving attachment actions on the same bounded neutral menu surface |
| Native Form / Menu / sheet / alert | settings, integrations, skill setup, editors and confirmation |

GlassSegmentedPicker/Control and arbitrary memoraCard(radius:) are retired.
The old colored SettingsIconStyle tiles and per-section Tint palette are retired;
settings and integration screens share one monochrome glyph implementation.
The protected bottom tab's UISegmentedControl is a separate implementation.

## Screen composition

Ask AI: compact sidebar/history/new-chat header; no idle decoration. A 32pt
message rhythm and selectable Markdown on the canvas. Keep stable TextField
identity, native composer Glass and 44pt controls. Candidates appear above the
composer and respect keyboard height.

Journal: primary ScrollView, flat week selector, minimal timeline glyphs and
hairlines. Neutral recap; expanded summary follows appearance and uses sections,
not nested translucent cards. The selected scenic image remains a small header
and the background-change action remains. Dates, health privacy, source links
and event editing keep their behavior.

Library: Files/Projects, sort/filter, selection/share/move/delete and gallery mode
remain. Titles lead, then kind/date/status and optional preview. Gallery groups
use 16pt neutral contours. Search and selection own the bottom edge when active.

Workspace: Chat / Files / Sources in that order, shared flat tabs, rows, empty
states and toolbar actions. Scoped Ask AI reads active-project evidence only;
privacy and membership are checked at execution and completion.

Record detail: common reading width/type for summary, transcript, decisions,
tasks and notes. Flat section tabs. Edit one block/cell in place; Markdown source
editing stays a deliberate context-menu action. Tables retain every value.
Audio, timestamps, source navigation and saving retain their existing paths.

Settings/sheets: native grouped Form, neutral glyphs, system presentation and
common action hierarchy. Preserve profile editing, permission explanations,
integration setup and the single sidebar settings entry. No fabricated service state.

## Interaction and accessibility

Liquid Glass belongs to navigation, bottom tabs, floating create and composer.
Keep the create label's matchedTransitionSource, compact popover and zoom.
Purposeful spring motion remains; Reduce Motion suppresses nonessential movement.
Loading reflects real operations; never invent progress or expose private reasoning.

Icon-only controls have accessible names. State uses text/traits/symbols as well
as color. Targets are at least 44pt, with background inside the label. Larger
text wraps/reflows; section tabs scroll. Use leading/trailing layout. Native
cursor, selection, VoiceOver and Japanese marked-text composition take priority.

## Verification

[Research and migration plan](docs/design-refresh/PLAN.md), before/after PNGs
and validation results live under docs/design-refresh/. Tests cover mention
range edits, scoped evidence/tools, persistence, navigation, Markdown and edit
round trips. Compilation is not visual/device proof. Live provider execution,
microphone, CloudKit and hardware require their actual configuration.
