"""Make thumbnail-only copies of generated corporate fixtures, not deliverable decks.

Quick Look thumbnails only the first page. Keep the actual appended page's parts
and master unchanged, removing only the original page's presentation-list entry.
Never use this on user files; input must be the synthetic two-page check outputs.
"""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET
from zipfile import ZipFile, ZIP_STORED

P = "{http://schemas.openxmlformats.org/presentationml/2006/main}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixtures", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    report = []
    names = [f"b{i:02}" for i in range(1, 31)] + [f"m{i:02}" for i in range(1, 36)]
    for name in names:
        with ZipFile(args.fixtures / (name + ".pptx")) as source:
            parts = {part: source.read(part) for part in source.namelist()}
        tree = ET.fromstring(parts["ppt/presentation.xml"])
        slides = tree.find(P + "sldIdLst")
        if slides is None or len(slides) != 2:
            raise ValueError("Expected original + one appended fixture page: " + name)
        slides.remove(slides[0])
        parts["ppt/presentation.xml"] = ET.tostring(tree, encoding="utf-8", xml_declaration=True)
        destination = args.output / (name + "-preview-only.pptx")
        with ZipFile(destination, "w", compression=ZIP_STORED) as output:
            for path, data in parts.items():
                output.writestr(path, data)
        report.append({"layout": name, "source": name + ".pptx", "previewOnly": destination.name,
                       "changedPart": "ppt/presentation.xml", "officeCompatibility": "unverified"})
    (args.output / "manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    print("65 thumbnail-only copies; original outputs untouched; only slide-list metadata changed")


if __name__ == "__main__":
    main()
