# Monochrome content × Native Liquid Glass

## Investigation and plan

Existing surfaces use system/grouped colors, `memoraCard`, per-view accent colors and custom AI glow palettes. Navigation glass lives in MemoraGlass, ProminentTabBar/UISegmentedControl, GlassSegmentedPicker/Control and toolbar helpers. Calendar selection uses glassEffectID and matched geometry; FAB uses its existing glass button/popover/zoom transition. Those structures, the three-tab order (Library / Journal / Ask AI), navigation paths and bottom clearances remain intact.

Implementation order: adaptive color and spacing tokens → shared cards/composer/chat components → Ask AI, Journal, Library, Record Detail → build and appearance/interaction checks. No database, model, network, recording, AI routing, task, sharing or access-policy behavior changes.

## Tokens

MemoraPalette uses dynamic UIColor providers for light/dark appearance and increased contrast. Content: white / 0B0B0B background, F7F7F7 / 171717 secondary surface, F5F5F5 / 202020 cards. Primary text/action: 0B0B0B / white. Secondary text: 737373 / A3A3A3. Card metadata uses 707070 on light cards (737373 on F5F5F5 gives only 4.35:1; 707070 exceeds 4.5:1). Contrast mode strengthens supporting text and border colors. Native `.primary` / `.secondary` remain for system controls.

After reviewing the result with the user, font weights, line spacing, section spacing, card sizes and corner radii were returned to their pre-redesign values. Only adaptive content colors and decorative color/shadow cleanup remain. Dynamic Type continues using the existing system fonts; there is no app-level text enlargement. Accessibility test settings in the simulator were restored to normal.

## Changes

- Ask AI: plain content background, neutral header mark, light-gray user messages, neutral source markers. Agent approval controls use contrasting monochrome actions. Composer action circle becomes black/white; its native glass, layout, focus, voice/attachment/send behavior and matched geometry are unchanged. Manual decorative shadows are removed.
- AI/voice expressions: existing animation timing, moving geometry and amplitude response remain. Their palette becomes faint grayscale. Existing animation masks/fades are retained rather than rebuilding the expressions. No new ornamental gradient is introduced.
- Journal: selected calendar day uses monochrome labels while retaining its native glass ID/morph. Timeline icons become neutral and connectors retain their existing width and use neutral color. Calendar event category colors, images, hero transition and editing remain.
- Library: white/black content canvas, neutral cards and metadata, original file typography and card geometry, neutral selection outline. Project contents/navigation remain the same.
- Record Detail: original headings, reading spacing and metadata layout. Participants, tabs, inline editing, playback, photos and action positions remain.
- Native glass helpers, tab bar, FAB and QuickAIComposer implementation are unchanged. Stock control tint, warnings, destructive roles, processing status colors, user-selected avatars/photos and calendar categories retain their meaning. Existing photo contrast scrims remain for legibility.

## Validation boundaries

Build and simulator verification are reported in the completion message. Static comparison confirms protected navigation/glass/FAB/scope/scroll/privacy files are unchanged and existing glass IDs, transition sources and presentations are retained. This comparison does not prove motion frame by frame or external-service operation. Real microphone/background audio, external recorders, configured AI providers and actual team sharing require device/service checks.
