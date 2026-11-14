# Memora brand assets (geometric v3)

The approved source is `memora-geometric-v3-svg.zip`, supplied on
2026-11-14. It replaces the earlier M-shaped mark, the old text logo and the
old app icon. The supplied SVGs are the design of record: no artwork is
redrawn, generated, tinted at runtime or downloaded.

The five solids read left to right as record, organize, understand, connect
and expand. The center `understand` shape is a true circle and stays the
quiet core in both the static mark and the thinking animation.

## Source of record

The six supplied SVGs are kept byte for byte in
`docs/brand/memora-geometric-v3/`:

- `…-mark-light.svg`, `…-mark-dark.svg`, `…-mark-adaptive.svg` — the 432×92
  mark.
- `…-lockup-light.svg`, `…-lockup-dark.svg`, `…-lockup-adaptive.svg` — the
  432×134 combination logo: mark above the outlined `MEMORA` wordmark.

`tools/checks/test_sidebar_brand_assets.py` guards their SHA-256 hashes.
Runtime drawing uses SwiftUI `Path`s converted from those same coordinates:

- `MemoraBrandShape` — the five solids in the 432×92 space.
- `MemoraBrandGeometry` — canvas sizes and the outlined wordmark strokes
  (`lineWidth` 1.65, square caps, miter joins).
- `MemoraBrandMark` — the static mark.
- `MemoraWordmark` — the wordmark cropped to its ink (271×21).
- `MemoraBrandLockup` — the vertical combination logo.
- `MemoraThinkingLogo` — the animated mark.

The supplied wordmark is already outline vector artwork, so the app bundles no
font file and no system font stands in for the letterforms. The letter size,
spacing, weight and uppercase form are exactly those of the approved lockup.

## Colors and appearances

Brand ink resolves with the app's existing appearance (`preferredColorScheme`):
`#0B0B0B` in light, `#F6F4EF` in dark. The logo has a transparent background;
spacing belongs to the SwiftUI layout, never to the artwork.

## Placement

- Sidebar header: the supplied `memora-sidebar-wordmark` SVG pair (346×65),
  drawn at 120pt wide (about 22.5pt high) with no geometric symbol. The asset
  keeps the original vector, its aspect ratio, and its light/dark fills
  (`#0B0B0B` / `#F6F4EF`); the header's existing margins, left alignment and
  search button are unchanged, and the wordmark is centered on the search
  button's vertical center.
- Onboarding header: the mark and wordmark side by side, preserving the row's
  previous height.
- Ask AI header: `MemoraWordmark`, as before.
- Ask AI thinking: `MemoraThinkingLogo` inside the existing status row.

## App icon

`docs/brand/appicon/…-light.svg` and `…-dark.svg` place the supplied lockup
inside a 1024×1024 canvas (content 640pt wide, centered). Light is white with
`#0B0B0B` ink; dark is `#0B0B0B` with `#F6F4EF` ink. The PNGs were rendered
with Quick Look, flattened to opaque RGB, and the tinted slot is a grayscale
conversion of the dark icon. All three are 1024×1024 with no alpha and no
rounded corners baked in; iOS applies the mask. The existing three
`AppIcon.appiconset` entries (light, dark, tinted) keep their filenames.

## Thinking animation

`MemoraThinkingLogo` draws the five solids independently over a 3.0s loop with
a 0.13s stagger. Offsets are 2.5pt vertically, rotation ±7°, scale 0.87–1.0
and opacity 0.55–1.0; the center circle uses 0.8pt, ±2°, 0.95–1.0 and
0.8–1.0. A 0.45s envelope brings the shapes out of rest. Because every shape's
phase returns to zero at the loop boundary, the final frame is exactly the
static mark.

State mapping uses the existing `AIChatMessage.isThinking` flow: the animated
logo shows while the reply has no text and no approval is pending; an approval
or streaming answer settles it to the static mark; completion, cancellation
and errors remove the row. The timeline pauses when the scene is inactive and
Reduce Motion replaces the animation with the static mark. The mark is hidden
from VoiceOver; the existing status line announces the state.

## Cleanup

`memora-wordmark.imageset`, `memora-symbol.imageset`, `MemoraSymbol.swift`
and the earlier M-shaped app icon PNGs are removed after their last reference
was switched. Interface glyphs, provider logos and unrelated artwork are
unchanged. Bundle identifiers, signing, the app name, navigation, data, models
and processing are unchanged.

## Verification

Run `python3 -B tools/checks/test_sidebar_brand_assets.py` and
`bitrig preview -platform iOS`; inspect sidebar, onboarding and Ask AI in both
appearances, and open the thinking state from your own Ask AI request or the
Settings diagnostics fixtures. Compilation alone is not visual validation.
