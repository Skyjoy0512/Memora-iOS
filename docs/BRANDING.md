# Canonical Memora brand assets

The approved source is `memora-brand-light-dark.zip`, supplied on 2026-11-10.
This replaces the former geometric sidebar mark and app icon. No artwork is
redrawn, generated, tinted at runtime, or downloaded.

## Artwork and appearances

- `App/Assets.xcassets/AppIcon.appiconset`: the original light and dark
  1024×1024 PNGs, byte for byte. Both are RGB without an alpha channel; all
  background pixels are opaque, including the corners. iOS supplies the mask.
  Light uses white / `#111113`; dark uses `#111113` / `#F8F8F8`, matching the
  supplied files rather than substituting pure black and white.
- The tinted slot is a grayscale conversion of the supplied dark PNG. The
  conversion changes only color space, preserving dimensions, M position,
  line weight, antialiasing and full-bleed background. iOS applies the chosen
  tint. Reproduce with macOS `sips -m
  '/System/Library/ColorSync/Profiles/Generic Gray Gamma 2.2 Profile.icc'
  memora-appicon-dark.png --out memora-appicon-tinted.png`.
- `memora-wordmark.imageset`: the original 410×68 SVG pair. The image has no
  background; the drawing bounds including strokes are 5.5…403.5 horizontally
  and 10.5…57.5 vertically. Keep that original canvas; external spacing belongs
  to the views. The sidebar displays it at 118pt wide (about 19.6pt high).
- `memora-symbol.imageset`: the original 432×432 SVG pair, including its
  `viewBox="290 287 444 451"`. Its existing viewport and uniform scaling are
  preserved; do not stretch its M to fill a square.
- Both vector sets preserve vector representation and original rendering,
  with the dark luminosity variant selected automatically by Asset Catalog
  in the app's existing appearance environment.

`MemoraWordmark` and `MemoraSymbol` are the shared components.
`SidebarBrandMark` retains the sidebar's accessibility identifier. Ask AI uses
only the header wordmark; a person-scoped chat still shows the person's name.
Onboarding's existing brand heading uses the symbol and wordmark. No idle
logo, loading animation or new launch-screen artwork is added.

## Scope and cleanup

The old `memora-sidebar-logo.imageset` and `AppIcon.appiconset/Icon.png` are
removed after their consumers are switched. The old macOS-only icon entry is
removed: this project targets iOS only. Functional Lucide icons, provider
logos and unrelated artwork remain as before. Bundle identifiers, signing,
app name, backend, models and navigation are unchanged.

The drawer's existing 28pt continuous clipping now encloses its closing wash
as well as the screen, preventing the rectangular wash from covering the
rounded corners. Existing drag, tap and Reduce Motion behavior are retained.

## Verification

Canonical byte hashes and appearance registrations are guarded by
`python3 -B tools/checks/test_sidebar_brand_assets.py`. The original PNGs'
measured ink bounds are identical: x=302…721, y=299…725. ImageIO inspection
confirmed alpha=255 throughout both icon inputs. The tinted input is 8-bit
grayscale without alpha. No duplicate PNG wordmarks or preview sheet are
bundled; the SVGs are the runtime source.

Build with `bitrig preview -platform iOS`; use the build log to check Asset
Catalog warnings. This Project.json has no Xcode test targets, so
`bitrig test` cannot run it. Repository presentation checks and actual
simulator checks must be reported separately from compilation.

### Results on 2026-11-10

- `bitrig preview -platform iOS`: succeeded and launched the updated preview.
  No Asset Catalog warnings. The build reported 11 warnings in unchanged
  location/OAuth/App Intents code; these are outside this brand change.
- `test_sidebar_brand_assets.py`: all 3 checks passed.
- `test_chat_surface_presentation.py`: all 8 checks passed.
- `bash tools/checks/run-design-refresh-checks.sh`: passed, including existing
  presentation, navigation, icon, composer, loading and motion checks.
- `git diff --check`: passed.
- iPhone 18 Pro Max built-in simulator: sidebar and Ask AI checked in light and
  dark, including live appearance switching, drawer navigation and the header's
  history/search menu. Rounded screen corners and wordmark proportions checked.
  Home Screen Default, Dark and Tinted were selected in iOS Customize and
  visibly rendered with the new M. Appearance settings restored after checking.
- iPhone 17e built-in simulator: onboarding and sidebar checked in both
  appearances, Ask AI in light; no logo clipping. Onboarding M geometry checked.
- Screenshots are saved in the ignored `build/brand-review/` directory:
  `home-light.png`, `home-dark.png`, `home-tinted.png`, `sidebar-light.png`,
  `sidebar-dark.png`, `askai-light.png`, `askai-dark.png`,
  `onboarding-light.png`, `onboarding-dark.png`, `sidebar-compact-light.png`,
  `sidebar-compact-dark.png` and `askai-compact-light.png`.
- Physical devices and App Store upload were not tested. The historical
  `tests/sidebar-glass.e2e.ts` logo size assertion was updated; this E2E suite
  was not executed. The verification above used actual simulator interactions
  plus repository checks, not an assertion that every E2E test passed.
