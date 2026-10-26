"""Report Quick Look omissions separately from OOXML structural checks.

Generate previews first with qlmanage -p -o <external-output> <fixture.pptx>.
This inspector is NOT a visual quality gate or proof of Office compatibility.
"""
import argparse
from html.parser import HTMLParser
import json
from pathlib import Path


class Slides(HTMLParser):
    def __init__(self):
        super().__init__()
        self.rows = []
        self.current = None
        self.depth = 0

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "div":
            if "slide" in attrs.get("class", "").split():
                self.current = {"slide": len(self.rows) + 1, "text": [], "images": [], "tables": 0}
                self.rows.append(self.current)
                self.depth = 0
            if self.current is not None:
                self.depth += 1
        if self.current is not None:
            if tag == "img":
                self.current["images"].append(attrs.get("src", ""))
            if tag == "table":
                self.current["tables"] += 1

    def handle_endtag(self, tag):
        if tag == "div" and self.current is not None:
            self.depth -= 1
            if self.depth == 0:
                self.current = None

    def handle_data(self, text):
        if self.current is not None and text.strip():
            self.current["text"].append(text.strip())


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("before", type=Path)
parser.add_argument("after", type=Path)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
report = {"renderer": "macOS Quick Look HTML", "officeRendering": "unverified", "visualQuality": "not approved"}
for key in ("before", "after"):
    slides = Slides()
    slides.feed(getattr(args, key).read_text())
    for row in slides.rows:
        text = "".join(row.pop("text"))
        row["chartTitle"] = next((title for title in ["棒グラフ", "折れ線グラフ", "円グラフ"] if title in text), None)
        row["chartImageMissing"] = row["chartTitle"] is not None and not row["images"]
    report[key] = slides.rows
args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(json.dumps(report, ensure_ascii=False))
