# Memora design refresh — 2026-10-19

## Inventory and scope

Baseline: clean `main`, SwiftUI iOS 26 / SDK 27.1. Roughly 880 App source files.
`MemoraPalette` owns adaptive neutrals but has no status/focus tokens. No shared
typography or spacing scale exists. `MemoraCard` accepts arbitrary radii;
Markdown has separate 5/6/7pt line spacing and 12/22pt block spacing. Summary
tables and inline editors duplicate row cards. `JournalSummaryView` forces dark
appearance and white text. Settings already opts into monochrome glyphs.
`MemoraGlass` and `MemoraMotion` are shared control/motion primitives.

Critical retained contracts: UISegmentedControl bottom tabs, create popover/zoom,
single Library path, scroll phase guards, primary Journal scroll view, SQLite
records and drafts, media references, capture, permissions, billing confirmation,
tool registry validation, external grants, project/record read-only execution.

Composer inventory: native SwiftUI TextField + UITextInput observation, UTF-16
mention ranges, SQLite draft mentions, registry-backed candidates, existing
approval/policy checks. Mentions are global-only. Project chat uses a separate
bounded read-only agent, not the global agent. No external write tools may be
exposed there. Baseline simulator @ insertion did not display candidates.
Window-wide outside-tap dismissal also conflicts with candidate selection.

## Official sources actually consulted

- https://github.com/openai/apps-sdk-ui
- https://developers.openai.com/plugins/concepts/ui-guidelines
- https://github.com/openai/apps-sdk-ui/blob/main/src/styles/variables-primitive.css
- https://github.com/openai/apps-sdk-ui/blob/main/src/styles/variables-semantic.css
- https://github.com/openai/apps-sdk-ui/blob/main/src/components/Markdown/Markdown.module.css

Retrieved 2026-10-19. These are Apps SDK web tokens, **not unpublished ChatGPT iOS
measurements**. No React, Tailwind runtime or WebView is introduced. Official
guidance asks for platform fonts, semantic colors, restrained imagery, consistent
spacing and accessible resizing. The following numerical analysis comes from
the CSS rather than inferred iOS screenshots.

| Foundation | Official web implementation | Memora native interpretation |
|---|---|---|
| Neutrals | gray-0 white/0D0D0D, gray-1000 inverse; secondary text 5D5D5D/AFAFAF | adaptive semantic palette; increase-contrast overrides |
| Surface | FFFFFF/212121, secondary F9F9F9/181818, elevated FFFFFF/303030 | white/212121 canvas, subtle neutral content surfaces; system presentation elevation |
| Type | system sans; 400/500/600/700; text 12/14/16/18px | SF + Japanese system fallback, Dynamic Type text styles; reading body 17pt default |
| Leading | text-md 24/16, text-lg 29/18 | scaled Japanese reading leading, natural tracking; no fixed web px mapping |
| Spacing | 4px base | 4pt scale; 20pt compact screen inset, 680pt reading width |
| Radius | 2,4,6,8,10,12,16,20,24,full | 8 small / 12 field / 16 content / 24 bubble-composer, capsule actions |
| Elevation | restrained 1/2/4/8px shadows | no content shadows; native sheets/menus/Glass controls |
| Buttons/input/menu | semantic variants, state colors, focus ring, disabled state | native Button/Toggle/Picker/TextField/Menu; 44pt minimum touch size |
| Status | danger red, warning orange, success green, blue focus | semantic adaptive colors plus text/symbol, never color alone |
| Icons | coherent monochrome outline icons | existing MemoraIcon registry, system-symbol resolution |
| Loading | dedicated indicators, shimmer available | real operation state only; static skeleton, Reduce Motion honored |
| Light/Dark | paired tokens and elevated surface variants | paired UIColor providers + native control semantics |
| Accessibility | AA contrast, resizing, accessible components | Dynamic Type, VoiceOver labels/headers, selection, keyboard/IME protection |

## Sequence and acceptance

1. Capture baseline screens; inventory and source analysis.
2. Replace shared foundations and components, then apply to reading/chat.
3. Apply to Journal, Library, workspace, settings and sheets; retire old guidance.
4. Connect unified @/+ picker to supported scoped execution; test real selection
   policy, IME/range edits, stale grants and source membership.
5. Build/preview each phase, host checks, existing + new E2E, Light/Dark and
   larger text/Reduce Motion observations. Commit each coherent phase.

Screenshot fixtures must be identified as fixtures; compilation is not device or
visual proof. Live provider, microphone, CloudKit and hardware checks require
configured services/devices and are reported separately.
