#!/usr/bin/env python3
"""Builds Memora's icon set from the Stratis UI icon set (CC BY 4.0).

The artwork comes from `stratis-icons-react`, the npm package that packages the
Stratis UI Icons into React SVG components. Stratis is a single-weight, mostly
stroke-based line set, so every weight group draws the same glyph; the stroke is
slightly heavier for bold text instead of swapping in a separate bold drawing.
Three brand marks (Apple, Google, Notion) have no Stratis equivalent and stay on
Phosphor Icons (MIT).

Each icon becomes a custom symbol (`.symbolset`), so it sizes with text, follows
`foregroundStyle`, and works in toolbars, menus, and UIKit exactly like a system
symbol.

Usage:
  curl -sSL -o st.tgz https://registry.npmjs.org/stratis-icons-react/-/stratis-icons-react-1.2.2.tgz
  mkdir -p st && tar xzf st.tgz -C st
  curl -sSL -o ph.tgz https://registry.npmjs.org/@phosphor-icons/core/-/core-2.1.1.tgz
  mkdir -p ph && tar xzf ph.tgz -C ph
  python3 tools/icons/generate.py st/package ph/package/assets

The raw values keep the names the app used before (SF Symbols names), because
project folders store theirs in the database.
"""
import json
import os
import re
import shutil
import sys

# raw value -> "source:name". `s:` is a Stratis icon component (trailing
# "Icon" optional); `p:` is a Phosphor icon (a trailing "!" uses its filled
# style). Only the brand marks without a Stratis equivalent stay on Phosphor.
ICONS = {
    # Navigation and chrome
    "calendar": "s:Calendar01",
    "calendar.fill": "s:Calendar01",
    "calendar.badge.checkmark": "s:CalendarCheck",
    "calendar.badge.checkmark.fill": "s:CalendarCheck",
    "folder": "s:Folder",
    "folder.fill": "s:Folder",
    "folder.badge.plus": "s:FolderPlus01",
    "folder.badge.questionmark": "s:FolderSearch01",
    "sparkles": "s:Stars",
    "sparkles.fill": "s:Stars",
    "checklist": "s:CheckSquareContained",
    "checklist.fill": "s:CheckSquareContained",
    "chat.bubble": "s:MessageCircle",
    "chat.bubble.fill": "s:MessageCircle",
    "plus": "s:Plus01",
    "xmark": "s:X01",
    "xmark.circle": "s:XCircleContained",
    "xmark.circle.fill": "s:XCircleContained",
    "checkmark": "s:Check01",
    "checkmark.circle": "s:CheckContained",
    "checkmark.circle.fill": "s:CheckContained",
    "checkmark.seal": "s:ShieldCheck",
    "checkmark.seal.fill": "s:ShieldCheck",
    "checkmark.square": "s:CheckSquareContained",
    "circle": "s:Circle",
    "circle.dotted": "s:Circle",
    "circle.lefthalf.filled": "s:Contrast",
    "chevron.down": "s:ChevronDown",
    "chevron.left": "s:ChevronLeft",
    "chevron.right": "s:ChevronRight",
    "ellipsis": "s:DotHorizontal",
    "line.3.horizontal": "s:Menu03",
    "line.3.horizontal.decrease": "s:Filter",
    "line.3.horizontal.decrease.circle": "s:Filter",
    "magnifyingglass": "s:Search02",
    "gearshape": "s:Settings",
    "gearshape.fill": "s:Settings",
    "square.and.pencil": "s:Edit01",
    "square.and.arrow.up": "s:Share",
    "square.and.arrow.down": "s:Download01",
    "arrow.up.right.square": "s:LinkExternal",
    "arrow.clockwise": "s:ArrowRotateRight01",
    "arrow.counterclockwise": "s:ArrowRotateLeft01",
    "arrow.triangle.2.circlepath": "s:Refresh01",
    "arrow.triangle.merge": "s:ArrowCurveLeftRight",
    "arrow.down": "s:DownArrow",
    "arrow.up": "s:ArrowUp",
    "arrow.up.left": "s:ArrowUpLeft",
    "arrow.up.right": "s:ArrowUpRight",
    "arrow.right.circle": "s:ArrowRightContained01",
    "arrow.uturn.backward": "s:ArrowCurveUpLeft",
    "arrow.down.doc": "s:FileDown01",
    "arrow.up.doc": "s:FileUp01",
    "rotate.right": "s:ArrowRotateRight01",
    "gobackward.15": "s:ArrowRotateLeft01",
    "goforward.15": "s:ArrowRotateRight01",
    "clock": "s:Clock01",
    "clock.fill": "s:Clock01",
    "clock.arrow.circlepath": "s:ClockBackward",
    "stopwatch": "s:Stopwatch01",
    "stopwatch.fill": "s:Stopwatch01",
    # Recording and media
    "waveform": "s:Waveform",
    "waveform.fill": "s:Waveform",
    "waveform.slash": "s:Waveform",
    "waveform.badge.mic": "s:Microphone01",
    "waveform.badge.plus": "s:FileAttach01",
    "waveform.badge.minus": "s:Waveform",
    "waveform.path.ecg": "s:Activity",
    "mic": "s:Microphone01",
    "mic.fill": "s:Microphone01",
    "mic.slash": "s:MicrophoneOff01",
    "play": "s:Play03",
    "play.fill": "s:Play01",
    "pause.fill": "s:Pause01",
    "stop.fill": "s:Stop01",
    "video": "s:VideoOn",
    "photo": "s:Image01",
    "photo.fill": "s:Image01",
    "photo.badge.plus": "s:ImageAdd",
    "photo.on.rectangle": "s:Image03",
    "camera": "s:Camera01",
    "crop": "s:Crop01",
    "paperclip": "s:Paperclip01",
    "dot.radiowaves.left.and.right": "s:Signal",
    "dot.radiowaves.left.and.right.fill": "s:Signal",
    "antenna.radiowaves.left.and.right": "s:Signal",
    "antenna.radiowaves.left.and.right.slash": "s:LinkBroken",
    "wifi.slash": "s:WifiOff",
    # Documents and text
    "doc": "s:File",
    "doc.text": "s:File02",
    "doc.text.fill": "s:File02",
    "text.document": "s:File02",
    "doc.richtext": "s:FileEdit01",
    "doc.questionmark": "s:FileQuestion01",
    "note.text": "s:Note01",
    "text.alignleft": "s:AlignLeft",
    "text.badge.plus": "s:Type01",
    "text.bubble": "s:MessageText01",
    "quote.bubble": "s:Quote",
    "questionmark.bubble": "s:HelpCircleContained",
    "list.bullet.rectangle": "s:List",
    "paragraph": "s:AlignJustify",
    "bold": "s:Bold01",
    "italic": "s:Italics01",
    "strikethrough": "s:TypeStrike01",
    "pencil": "s:Pencil01",
    "pin": "s:Marker01",
    "rectangle.grid.2x2": "s:Grid01",
    "rectangle.grid.2x2.fill": "s:Grid04Filled",
    "square.grid.2x2": "s:Grid02",
    "rectangle.stack": "s:Layers01",
    "rectangle.stack.fill": "s:Layers01",
    "rectangle.stack.badge.play": "s:MediaStrip01",
    "square.stack.3d.up": "s:Layers02",
    "briefcase": "s:Bag01",
    "tray": "s:Inbox01",
    "trash": "s:Trash01",
    "trash.fill": "s:Trash01",
    "trash.slash": "s:Delete",
    # People
    "person": "s:UserProfile01",
    "person.fill": "s:UserProfile01",
    "person.2": "s:UsersProfiles01",
    "person.3": "s:UsersProfiles02",
    "person.3.fill": "s:UsersProfiles02",
    "person.badge.key": "s:Logout01",
    "person.badge.plus": "s:UserProfileAdd01",
    "person.crop.circle": "s:UserProfileCircle",
    "person.crop.circle.fill": "s:UserProfileCircle",
    "person.crop.circle.badge.xmark": "s:UserProfileX",
    "face.smiling": "s:SmileyHappy",
    "face.smiling.fill": "s:SmileyHappy",
    "rectangle.portrait.and.arrow.right": "s:Logout01",
    "hand.raised": "s:Pointer01",
    "hand.raised.fill": "s:Pointer01",
    # Places and system
    "location": "s:Compass1",
    "location.fill": "s:Compass1",
    "mappin.slash": "s:Marker03",
    "mappin.slash.fill": "s:Marker03",
    "sun.max": "s:Sun01",
    "sunrise": "s:SunUp",
    "moon": "s:Moon01",
    "cloud": "s:Cloud01",
    "cloud.fill": "s:Cloud01",
    "icloud.slash": "s:Cloud01",
    "internaldrive": "s:Server01",
    "internaldrive.fill": "s:Server01",
    "externaldrive": "s:Server03",
    "externaldrive.fill": "s:Server03",
    "lock.shield": "s:ShieldCheck",
    "lock.shield.fill": "s:ShieldCheck",
    "faceid": "s:FaceId01",
    "faceid.fill": "s:FaceId01",
    "key": "s:Key01",
    "key.fill": "s:Key01",
    "link": "s:Link",
    "iphone": "s:Iphone02",
    "iphone.fill": "s:Iphone02",
    "iphone.and.arrow.forward": "s:Send01",
    "desktopcomputer": "s:Computer",
    "cpu": "s:Server02",
    "cpu.fill": "s:Server02",
    "brain": "s:Lightbulb01",
    "brain.fill": "s:Lightbulb01",
    "crown": "s:Star01",
    "crown.fill": "s:Star01",
    "bell": "s:Bell01",
    "bell.fill": "s:Bell01",
    "info": "s:InformationCircleContained",
    "info.circle": "s:InformationCircleContained",
    "info.circle.fill": "s:InformationCircleContained",
    "questionmark": "s:HelpCircleContained",
    "questionmark.circle": "s:HelpCircleContained",
    "questionmark.circle.fill": "s:HelpCircleContained",
    "exclamationmark.circle": "s:AlertCircle",
    "exclamationmark.triangle": "s:AlertTriangle",
    "exclamationmark.triangle.fill": "s:AlertTriangle",
    "envelope": "s:Mail01",
    "apple.logo": "p:apple-logo",
    "g.circle": "p:google-logo",
    "notion.logo": "p:notion-logo",
    "plugs.connected": "s:Plug01",
    "plugs.connected.fill": "s:Plug01",
    "paintpalette": "s:Palette",
    "slider.horizontal.3": "s:AudioSettings01",
    "chart.bar": "s:BarChart01",
    "chart.bar.fill": "s:BarChart01",
}

SCALE = 0.50
BOX = 256 * SCALE
INSET = 14 * SCALE
# Keep semibold toolbar labels from turning every outline into a heavy glyph.
WEIGHTS = [
    ("Ultralight", "light"), ("Thin", "light"), ("Light", "light"),
    ("Regular", "regular"), ("Medium", "regular"),
    ("Semibold", "regular"), ("Bold", "bold"), ("Heavy", "bold"), ("Black", "bold"),
]
SCALES = {"S": (696, 625.541), "M": (1126, 1055.54), "L": (1556, 1485.54)}

# Stratis is a single-weight set, so the weight groups differ only by stroke.
# The set ships 2.0; the app draws a noticeably heavier stroke than the set.
STROKE = {"light": 2.6, "regular": 3.0, "bold": 3.6}
DRAWING = {"path", "circle", "rect", "line", "polyline", "polygon", "ellipse"}


def read_stratis(root):
    """Returns {name: (viewBox, [element, ...])} for every Stratis icon."""
    src = open(f"{root}/dist/index.mjs").read()
    icons = {}
    for block in re.split(r"\nvar ", src):
        match = re.match(r"([A-Za-z0-9_]+Icon) = /\* @__PURE__ \*/ Object\.assign\(", block)
        if not match:
            continue
        view_box = re.search(r'viewBox:\s*"([^"]+)"', block)
        elements = []
        for element in re.finditer(r'createElement\("(\w+)",\s*(\{[^{}]*\})', block):
            tag, attrs = element.group(1), element.group(2)
            if tag not in DRAWING:
                continue
            values = {}
            for attr in re.finditer(r'([A-Za-z_][A-Za-z0-9_]*)\s*:\s*("(?:[^"\\]|\\.)*"|[A-Za-z0-9_.-]+)', attrs):
                key, value = attr.group(1), attr.group(2)
                if value.startswith('"'):
                    try:
                        value = json.loads(value)
                    except ValueError:
                        pass
                values[key] = value
            values["_tag"] = tag
            elements.append(values)
        icons[match.group(1)] = (view_box.group(1) if view_box else "0 0 24 24", elements)
    return icons


def stratis_body(elements, stroke):
    """Renders one weight group's glyph. Coloured fills/strokes become the
    symbol's own black, which the system recolours."""
    body = []
    for element in elements:
        parts = []
        filled = element.get("fill") == "color"
        if "d" in element:
            parts.append(f'd="{element["d"]}"')
        for name in ("cx", "cy", "r", "x", "y", "width", "height", "rx", "ry",
                     "x1", "y1", "x2", "y2", "points"):
            if name in element:
                parts.append(f'{name}="{element[name]}"')
        if element.get("fillRule"):
            parts.append(f'fill-rule="{element["fillRule"]}"')
        if element.get("clipRule"):
            parts.append(f'clip-rule="{element["clipRule"]}"')
        if filled:
            parts.append('fill="#000"')
        else:
            parts.append('fill="none"')
            parts.append('stroke="#000"')
            parts.append(f'stroke-width="{stroke}"')
            parts.append(f'stroke-linecap="{element.get("strokeLinecap", "round")}"')
            parts.append(f'stroke-linejoin="{element.get("strokeLinejoin", "round")}"')
        body.append(f'   <{element["_tag"]} {" ".join(parts)}/>')
    return "\n".join(body)


def phosphor_paths(root, style, name):
    suffix = "" if style == "regular" else f"-{style}"
    src = open(f"{root}/{style}/{name}{suffix}.svg").read()
    return [re.search(r' d="([^"]+)"', m.group(1)).group(1)
            for m in re.finditer(r"<path([^>]*)/>", src)]


def stratis_glyph(icon, style):
    view_box, elements = icon
    _, _, width, height = (float(v) for v in view_box.split())
    scale = BOX / max(width, height)
    body = stratis_body(elements, STROKE[style])
    return body, scale, width, height


def phosphor_glyph(root, name, filled, style):
    body = "\n".join(f'   <path d="{d}"/>' for d in phosphor_paths(root, "fill" if filled else style, name))
    return body, SCALE, 256.0, 256.0


def glyph(source, name, style, stratis, phosphor_root):
    if source == "s":
        component = name if name.endswith("Icon") else f"{name}Icon"
        return stratis_glyph(stratis[component], style)
    filled = name.endswith("!")
    return phosphor_glyph(phosphor_root, name.rstrip("!"), filled, style)


def template(source, name, stratis, phosphor_root):
    guides, glyphs = [], []
    x = 300.0
    note = (f'Stratis UI Icons "{name}" (CC BY 4.0).'
            if source == "s" else f'Phosphor Icons "{name}" (MIT).')
    for weight, style in WEIGHTS:
        variant = f"{weight}-M"
        top = SCALES["M"][0] - 35.23 - BOX / 2
        left_margin, right_margin = x + INSET, x + BOX - INSET
        guides.append(f'  <line id="left-margin-{variant}" style="fill:none;stroke:#00AEEF;stroke-width:0.5;" x1="{left_margin:.3f}" x2="{left_margin:.3f}" y1="1030.79" y2="1150.12"/>')
        guides.append(f'  <line id="right-margin-{variant}" style="fill:none;stroke:#00AEEF;stroke-width:0.5;" x1="{right_margin:.3f}" x2="{right_margin:.3f}" y1="1030.79" y2="1150.12"/>')
        body, scale, width, height = glyph(source, name, style, stratis, phosphor_root)
        tx = x + (BOX - width * scale) / 2
        ty = top + (BOX - height * scale) / 2
        glyphs.append(f'  <g id="{variant}" transform="matrix({scale:.6f} 0 0 {scale:.6f} {tx:.3f} {ty:.3f})">\n{body}\n  </g>')
        x += 300
    lines = []
    for scale, (baseline, capline) in SCALES.items():
        lines.append(f'  <line id="Baseline-{scale}" style="fill:none;stroke:#27AAE1;stroke-width:0.5;" x1="263" x2="3036" y1="{baseline}" y2="{baseline}"/>')
        lines.append(f'  <line id="Capline-{scale}" style="fill:none;stroke:#27AAE1;stroke-width:0.5;" x1="263" x2="3036" y1="{capline}" y2="{capline}"/>')
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
 <!--{note} Generated by tools/icons/generate.py.-->
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
    stratis_root = sys.argv[1]
    phosphor_root = sys.argv[2] if len(sys.argv) > 2 else None
    stratis = read_stratis(stratis_root)
    if any(value.startswith("p:") for value in ICONS.values()) and not phosphor_root:
        sys.exit("This table keeps brand marks on Phosphor; pass the Phosphor assets directory too")
    repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    catalog = os.path.join(repo, "Shared", "Icons.xcassets")
    shutil.rmtree(catalog, ignore_errors=True)
    os.makedirs(catalog)
    json.dump({"info": {"author": "xcode", "version": 1}}, open(f"{catalog}/Contents.json", "w"), indent=2)

    for raw, entry in ICONS.items():
        source, name = entry.split(":", 1)
        asset = f"memora.{raw}"
        folder = f"{catalog}/{asset}.symbolset"
        os.makedirs(folder)
        open(f"{folder}/{asset}.svg", "w").write(template(source, name, stratis, phosphor_root))
        json.dump({"info": {"author": "xcode", "version": 1},
                   "symbols": [{"filename": f"{asset}.svg", "idiom": "universal"}]},
                  open(f"{folder}/Contents.json", "w"), indent=2)

    cases = "\n".join(f'  case {case_name(raw)} = "{raw}"' for raw in sorted(ICONS))
    swift = f'''// Generated by tools/icons/generate.py. Do not edit by hand; add an icon to
// the table there and run the script again.

/// Every icon the app draws. Each one is a custom symbol built from the Stratis
/// UI icon set, so it scales with text and takes the foreground style like a
/// system symbol. Raw values keep the older SF Symbols names so stored choices
/// (a project's icon) still resolve.
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
