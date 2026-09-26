# Memora icons

The app draws its icons from `Shared/Icons.xcassets`, a set of custom symbols
built from the [Stratis UI Icons](https://www.figma.com/community/file/1177180791780461401)
line set, packaged for npm as
[`stratis-icons-react`](https://www.npmjs.com/package/stratis-icons-react)
(CC BY 4.0). They behave like system symbols: they size with text and take
`foregroundStyle`. Stratis is a single-weight, mostly stroke-based set, so every
weight group draws the same glyph and bold text only widens the stroke. The
normalized canvas scale is 0.40, giving the glyphs more breathing room.

Three brand marks — Apple, Google, and Notion — have no Stratis equivalent and
stay on [Phosphor Icons](https://phosphoricons.com) (MIT).

The navigation set pairs the same silhouette in outline and fill: simple
folder, blank calendar, check square, and round chat bubble. Only the selected
tab uses fill. Both states are rendered at the same size and cached, so a tap
does not perform image rendering or replace the native selection animation.
Stratis has no filled counterpart for these, so the two states share one glyph
and differ only in tint.

Motion is tied to state: the create icon turns as its menu opens, task completion
gets a brief bounce, and voice input / AI processing gets a subtle pulse.
Custom movement respects Reduce Motion. Do not add decorative entrance loops.

Custom symbols are resolved through `UIImage` before SwiftUI receives them.
Toolbar buttons draw that image explicitly with a scaled 21pt frame; settings
rows use an explicit icon/text stack and a scaled 29pt tile. Do not rely on a
container's inferred label style to decide whether these icons are visible.

`tools/checks/IconRenderingChecks.swift` checks the compiled catalog for visible
pixels across all icons, three scales, and two weights. An icon passes when it
draws in any one configuration; AppKit can rasterize a single configuration
blank for a stroke-only symbol, which is a macOS quirk rather than a broken
asset. Compile it together with `Shared/MemoraIcon.swift` using
`swiftc -parse-as-library -framework AppKit`, then pass the built app bundle path
to the executable. This tests asset rendering on macOS; it does not substitute
for observing the app's iOS controls.

Code refers to them through `MemoraIcon` (`Shared/MemoraIcon.swift`), which is
generated together with the catalog:

```sh
curl -sSL -o /tmp/st.tgz https://registry.npmjs.org/stratis-icons-react/-/stratis-icons-react-1.2.2.tgz
mkdir -p /tmp/st && tar xzf /tmp/st.tgz -C /tmp/st
curl -sSL -o /tmp/ph.tgz https://registry.npmjs.org/@phosphor-icons/core/-/core-2.1.1.tgz
mkdir -p /tmp/ph && tar xzf /tmp/ph.tgz -C /tmp/ph
python3 tools/icons/generate.py /tmp/st/package /tmp/ph/package/assets
```

To add an icon, add a row to `ICONS` in `generate.py` and run it again.

AI provider logos (`App/Assets.xcassets/Providers`) come from
[Lobe Icons](https://github.com/lobehub/lobe-icons) (MIT). The marks belong to
their companies and are shown only to identify each provider.

## Licenses

Stratis UI Icons — Creative Commons Attribution 4.0 International (CC BY 4.0).
Original work:
[Stratis UI Icons - 1000+ Free Figma icons](https://www.figma.com/community/file/1177180791780461401).
License: <https://creativecommons.org/licenses/by/4.0/>. Changes made: the
icons were exported from `stratis-icons-react` and converted into custom symbol
SVGs. The original authors do not endorse this app.

Phosphor Icons (brand marks only) — MIT License, Copyright (c) 2023 Phosphor Icons.
Lobe Icons — MIT License, Copyright (c) 2023 LobeHub.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
