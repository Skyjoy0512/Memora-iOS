#!/usr/bin/env python3
"""Builds Memora's icon set from Phosphor Icons (MIT).

Each icon becomes a custom symbol (`.symbolset`), so it sizes with text, follows
`foregroundStyle`, and works in toolbars, menus, and UIKit exactly like a system
symbol. Chrome uses a restrained regular stroke, including beside semibold text;
bold accessibility text still receives the heavier variant.

Usage:
  curl -sSL -o ph.tgz https://registry.npmjs.org/@phosphor-icons/core/-/core-2.1.1.tgz
  mkdir ph && tar xzf ph.tgz -C ph
  python3 tools/icons/generate.py ph/package/assets

The raw values keep the names the app used before (SF Symbols names), because
project folders store theirs in the database.
"""
import json
import os
import re
import shutil
import sys

# raw value -> Phosphor name. A trailing "!" uses Phosphor's filled style.
ICONS = {
    # Navigation and chrome
    "calendar": "calendar-blank",
    "calendar.fill": "calendar-blank!",
    "calendar.badge.checkmark": "calendar-check",
    "calendar.badge.checkmark.fill": "calendar-check!",
    "folder": "folder-simple",
    "folder.fill": "folder-simple!",
    "folder.badge.plus": "folder-plus",
    "folder.badge.questionmark": "folder-dashed",
    "sparkles": "sparkle",
    "sparkles.fill": "sparkle!",
    "checklist": "check-square",
    "checklist.fill": "check-square!",
    "chat.bubble": "chat-circle",
    "chat.bubble.fill": "chat-circle!",
    "plus": "plus",
    "xmark": "x",
    "xmark.circle": "x-circle",
    "xmark.circle.fill": "x-circle!",
    "checkmark": "check",
    "checkmark.circle": "check-circle",
    "checkmark.circle.fill": "check-circle!",
    "checkmark.seal": "seal-check",
    "checkmark.seal.fill": "seal-check!",
    "checkmark.square": "check-square",
    "circle": "circle",
    "circle.dotted": "circle-dashed",
    "circle.lefthalf.filled": "circle-half",
    "chevron.down": "caret-down",
    "chevron.left": "caret-left",
    "chevron.right": "caret-right",
    "ellipsis": "dots-three",
    "line.3.horizontal": "list",
    "line.3.horizontal.decrease": "funnel-simple",
    "line.3.horizontal.decrease.circle": "funnel-simple",
    "magnifyingglass": "magnifying-glass",
    "gearshape": "gear",
    "gearshape.fill": "gear!",
    "square.and.pencil": "pencil-simple-line",
    "square.and.arrow.up": "export",
    "square.and.arrow.down": "tray-arrow-down",
    "arrow.up.right.square": "arrow-square-out",
    "arrow.clockwise": "arrow-clockwise",
    "arrow.counterclockwise": "arrow-counter-clockwise",
    "arrow.triangle.2.circlepath": "arrows-clockwise",
    "arrow.triangle.merge": "arrows-merge",
    "arrow.down": "arrow-down",
    "arrow.up": "arrow-up",
    "arrow.up.left": "arrow-up-left",
    "arrow.up.right": "arrow-up-right",
    "arrow.right.circle": "arrow-circle-right",
    "arrow.uturn.backward": "arrow-u-up-left",
    "arrow.down.doc": "file-arrow-down",
    "arrow.up.doc": "file-arrow-up",
    "rotate.right": "arrow-clockwise",
    "gobackward.15": "arrow-arc-left",
    "goforward.15": "arrow-arc-right",
    "clock": "clock",
    "clock.fill": "clock!",
    "clock.arrow.circlepath": "clock-counter-clockwise",
    "stopwatch": "timer",
    "stopwatch.fill": "timer!",
    # Recording and media
    "waveform": "waveform",
    "waveform.fill": "waveform!",
    "waveform.slash": "waveform-slash",
    "waveform.badge.mic": "record",
    "waveform.badge.plus": "file-audio",
    "waveform.badge.minus": "waveform-slash",
    "waveform.path.ecg": "pulse",
    "mic": "microphone",
    "mic.fill": "microphone!",
    "mic.slash": "microphone-slash",
    "play": "play",
    "play.fill": "play!",
    "pause.fill": "pause!",
    "stop.fill": "stop!",
    "video": "video-camera",
    "photo": "image",
    "photo.fill": "image!",
    "photo.badge.plus": "camera-plus",
    "photo.on.rectangle": "images",
    "camera": "camera",
    "crop": "crop",
    "paperclip": "paperclip",
    "dot.radiowaves.left.and.right": "broadcast",
    "dot.radiowaves.left.and.right.fill": "broadcast!",
    "antenna.radiowaves.left.and.right": "broadcast",
    "antenna.radiowaves.left.and.right.slash": "link-break",
    "wifi.slash": "wifi-slash",
    # Documents and text
    "doc": "file",
    "doc.text": "file-text",
    "doc.text.fill": "file-text!",
    "text.document": "file-text",
    "doc.richtext": "article",
    "doc.questionmark": "file-dashed",
    "note.text": "note",
    "text.alignleft": "text-align-left",
    "text.badge.plus": "text-t",
    "text.bubble": "chat-text",
    "quote.bubble": "quotes",
    "questionmark.bubble": "seal-question",
    "list.bullet.rectangle": "list-bullets",
    "paragraph": "paragraph",
    "bold": "text-b",
    "italic": "text-italic",
    "strikethrough": "text-strikethrough",
    "pencil": "pencil-simple",
    "pin": "push-pin",
    "rectangle.grid.2x2": "squares-four",
    "rectangle.grid.2x2.fill": "squares-four!",
    "square.grid.2x2": "squares-four",
    "rectangle.stack": "stack",
    "rectangle.stack.fill": "stack!",
    "rectangle.stack.badge.play": "cards",
    "square.stack.3d.up": "stack-simple",
    "briefcase": "briefcase",
    "tray": "tray",
    "trash": "trash",
    "trash.fill": "trash!",
    "trash.slash": "prohibit",
    # People
    "person": "user",
    "person.fill": "user!",
    "person.2": "users",
    "person.3": "users",
    "person.3.fill": "users!",
    "person.badge.key": "sign-in",
    "person.badge.plus": "user-plus",
    "person.crop.circle": "user-circle",
    "person.crop.circle.fill": "user-circle!",
    "person.crop.circle.badge.xmark": "user-circle-minus",
    "face.smiling": "smiley",
    "face.smiling.fill": "smiley!",
    "rectangle.portrait.and.arrow.right": "sign-out",
    "hand.raised": "hand",
    "hand.raised.fill": "hand!",
    # Places and system
    "location": "navigation-arrow",
    "location.fill": "navigation-arrow!",
    "mappin.slash": "prohibit",
    "mappin.slash.fill": "prohibit!",
    "sun.max": "sun",
    "sunrise": "sun-horizon",
    "moon": "moon",
    "cloud": "cloud",
    "cloud.fill": "cloud!",
    "icloud.slash": "cloud-slash",
    "internaldrive": "hard-drive",
    "internaldrive.fill": "hard-drive!",
    "externaldrive": "archive",
    "externaldrive.fill": "archive!",
    "lock.shield": "shield-check",
    "lock.shield.fill": "shield-check!",
    "faceid": "scan-smiley",
    "faceid.fill": "scan-smiley!",
    "key": "key",
    "key.fill": "key!",
    "link": "link",
    "iphone": "device-mobile",
    "iphone.fill": "device-mobile!",
    "iphone.and.arrow.forward": "export",
    "desktopcomputer": "desktop",
    "cpu": "cpu",
    "cpu.fill": "cpu!",
    "brain": "brain",
    "brain.fill": "brain!",
    "crown": "crown",
    "crown.fill": "crown!",
    "bell": "bell",
    "bell.fill": "bell!",
    "info": "info",
    "info.circle": "info",
    "info.circle.fill": "info!",
    "questionmark": "question",
    "questionmark.circle": "question",
    "questionmark.circle.fill": "question!",
    "exclamationmark.circle": "warning-circle",
    "exclamationmark.triangle": "warning",
    "exclamationmark.triangle.fill": "warning!",
    "envelope": "envelope-simple",
    "apple.logo": "apple-logo",
    "g.circle": "google-logo",
    "notion.logo": "notion-logo",
    "plugs.connected": "plugs-connected",
    "plugs.connected.fill": "plugs-connected!",
    "paintpalette": "palette",
    "slider.horizontal.3": "sliders-horizontal",
    "chart.bar": "chart-bar",
    "chart.bar.fill": "chart-bar!",
}

SCALE = 0.40
BOX = 256 * SCALE
INSET = 14 * SCALE
# Keep semibold toolbar labels from turning every outline into a heavy glyph.
WEIGHTS = [
    ("Ultralight", "light"), ("Thin", "light"), ("Light", "light"),
    ("Regular", "regular"), ("Medium", "regular"),
    ("Semibold", "regular"), ("Bold", "bold"), ("Heavy", "bold"), ("Black", "bold"),
]
SCALES = {"S": (696, 625.541), "M": (1126, 1055.54), "L": (1556, 1485.54)}


def paths(root, style, name):
    suffix = "" if style == "regular" else f"-{style}"
    src = open(f"{root}/{style}/{name}{suffix}.svg").read()
    return [re.search(r' d="([^"]+)"', m.group(1)).group(1)
            for m in re.finditer(r"<path([^>]*)/>", src)]


def template(root, name, filled):
    guides, glyphs = [], []
    x = 300.0
    for weight, style in WEIGHTS:
        variant = f"{weight}-M"
        source = "fill" if filled else style
        top = SCALES["M"][0] - 35.23 - BOX / 2
        left_margin, right_margin = x + INSET, x + BOX - INSET
        guides.append(f'  <line id="left-margin-{variant}" style="fill:none;stroke:#00AEEF;stroke-width:0.5;" x1="{left_margin:.3f}" x2="{left_margin:.3f}" y1="1030.79" y2="1150.12"/>')
        guides.append(f'  <line id="right-margin-{variant}" style="fill:none;stroke:#00AEEF;stroke-width:0.5;" x1="{right_margin:.3f}" x2="{right_margin:.3f}" y1="1030.79" y2="1150.12"/>')
        body = "\n".join(f'   <path d="{d}"/>' for d in paths(root, source, name))
        glyphs.append(f'  <g id="{variant}" transform="matrix({SCALE} 0 0 {SCALE} {x:.3f} {top:.3f})">\n{body}\n  </g>')
        x += 300
    lines = []
    for scale, (baseline, capline) in SCALES.items():
        lines.append(f'  <line id="Baseline-{scale}" style="fill:none;stroke:#27AAE1;stroke-width:0.5;" x1="263" x2="3036" y1="{baseline}" y2="{baseline}"/>')
        lines.append(f'  <line id="Capline-{scale}" style="fill:none;stroke:#27AAE1;stroke-width:0.5;" x1="263" x2="3036" y1="{capline}" y2="{capline}"/>')
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
 <!--Phosphor Icons "{name}" (MIT). Generated by tools/icons/generate.py.-->
 <g id="Notes">
  <text id="template-version" style="stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;" transform="matrix(1 0 0 1 3036 1933)">Template v.3.0</text>
 </g>
 <g id="Guides">
{chr(10).join(lines)}
{chr(10).join(guides)}
 </g>
 <g id="Symbols">
{chr(10).join(glyphs)}
 </g>
</svg>
'''


def case_name(raw):
    parts = raw.split(".")
    return parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])


def main():
    root = sys.argv[1]
    repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    catalog = os.path.join(repo, "Shared", "Icons.xcassets")
    shutil.rmtree(catalog, ignore_errors=True)
    os.makedirs(catalog)
    json.dump({"info": {"author": "xcode", "version": 1}}, open(f"{catalog}/Contents.json", "w"), indent=2)

    for raw, source in ICONS.items():
        filled = source.endswith("!")
        name = source.rstrip("!")
        asset = f"memora.{raw}"
        folder = f"{catalog}/{asset}.symbolset"
        os.makedirs(folder)
        open(f"{folder}/{asset}.svg", "w").write(template(root, name, filled))
        json.dump({"info": {"author": "xcode", "version": 1},
                   "symbols": [{"filename": f"{asset}.svg", "idiom": "universal"}]},
                  open(f"{folder}/Contents.json", "w"), indent=2)

    cases = "\n".join(f'  case {case_name(raw)} = "{raw}"' for raw in sorted(ICONS))
    swift = f'''// Generated by tools/icons/generate.py. Do not edit by hand; add an icon to
// the table there and run the script again.

/// Every icon the app draws. Each one is a custom symbol built from Phosphor
/// Icons, so it scales with text and takes the foreground style like a system
/// symbol. Raw values keep the older SF Symbols names so stored choices (a
/// project's icon) still resolve.
enum MemoraIcon: String, CaseIterable, Sendable {{
{cases}

  /// The symbol's name in `Icons.xcassets`.
  var assetName: String {{ "memora.\\(rawValue)" }}
}}
'''
    open(os.path.join(repo, "Shared", "MemoraIcon.swift"), "w").write(swift)
    print(f"{len(ICONS)} icons written to {catalog}")


if __name__ == "__main__":
    main()
