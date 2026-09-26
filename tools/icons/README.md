# Memora icons

The app draws its icons from `Shared/Icons.xcassets`, a set of custom symbols
built from [Phosphor Icons](https://phosphoricons.com) (MIT). They behave like
system symbols: they size with text and take `foregroundStyle`. Regular and
semibold text use the regular outline; bold text keeps the heavier variant.
The normalized canvas scale is 0.40, giving the glyphs more breathing room.

The navigation set pairs the same silhouette in outline and fill: simple
folder, blank calendar, check square, and round chat bubble. Only the selected
tab uses fill. Both states are rendered at the same size and cached, so a tap
does not perform image rendering or replace the native selection animation.

Motion is tied to state: the create icon turns as its menu opens, task completion
gets a brief bounce, and voice input / AI processing gets a subtle pulse.
Custom movement respects Reduce Motion. Do not add decorative entrance loops.

Code refers to them through `MemoraIcon` (`Shared/MemoraIcon.swift`), which is
generated together with the catalog:

```sh
curl -sSL -o /tmp/ph.tgz https://registry.npmjs.org/@phosphor-icons/core/-/core-2.1.1.tgz
mkdir -p /tmp/ph && tar xzf /tmp/ph.tgz -C /tmp/ph
python3 tools/icons/generate.py /tmp/ph/package/assets
```

To add an icon, add a row to `ICONS` in `generate.py` and run it again.

AI provider logos (`App/Assets.xcassets/Providers`) come from
[Lobe Icons](https://github.com/lobehub/lobe-icons) (MIT). The marks belong to
their companies and are shown only to identify each provider.

## Licenses

Phosphor Icons — MIT License, Copyright (c) 2023 Phosphor Icons.
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
