"""Independent stdlib ZIP/XML inspection of the development engine PoC."""
import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("directory", type=Path)
args = parser.parse_args()
ns = {"a": "http://schemas.openxmlformats.org/drawingml/2006/main",
      "p": "http://schemas.openxmlformats.org/presentationml/2006/main",
      "c": "http://schemas.openxmlformats.org/drawingml/2006/chart"}


def inspect(path, count):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
        assert len(archive.infolist()) < 1000
        assert sum(i.file_size for i in archive.infolist()) < 100_000_000
        parts = {i.filename: archive.read(i) for i in archive.infolist() if not i.is_dir()}
    xml = {name: ET.fromstring(data) for name, data in parts.items() if name.endswith((".xml", ".rels"))}
    slides = sorted(name for name in xml if re.fullmatch(r"ppt/slides/slide\d+\.xml", name))
    assert len(slides) == count
    assert len([n for n in xml if re.fullmatch(r"ppt/charts/chart\d+\.xml", n)]) == 3
    assert len([n for n in parts if n.startswith("ppt/embeddings/") and n.endswith(".xlsx")]) == 3
    assert sum(len(xml[s].findall(".//a:tbl", ns)) for s in slides) == 1
    assert sum(len(xml[s].findall(".//p:pic", ns)) for s in slides) >= 1
    notes = [n for n, x in xml.items() if x.tag == "{" + ns["p"] + "}notes"]
    assert len(notes) == count
    text = "\n".join("".join(xml[s].itertext()) for s in slides)
    assert "Before / After" in text and "確認してから反映" in text
    for s in slides:
        ids = [e.attrib["id"] for e in xml[s].findall(".//p:cNvPr", ns)]
        assert len(set(ids)) == len(ids)
    return parts, xml, text


before, before_xml, before_text = inspect(args.directory / "pptxgenjs.pptx", 8)
after, after_xml, after_text = inspect(args.directory / "office-kit-edited.pptx", 9)
assert "{{company}}" in before_text and "{{company}}" not in after_text
assert "Memora 検証会社" in after_text and "複製して編集：日本語の見出し" in after_text
assert any("変更後のノート" in "".join(x.itertext()) for n, x in after_xml.items() if n.startswith("ppt/notesSlides/"))
values = [v.text for v in after_xml["ppt/charts/chart1.xml"].findall(".//c:val/c:numRef/c:numCache/c:pt/c:v", ns)]
assert values == ["22", "36", "48"]
style_parts = [n for n in before if n.startswith(("ppt/theme/", "ppt/slideMasters/", "ppt/slideLayouts/"))]
assert style_parts and all(n in after for n in style_parts)
result = {"sourceSlides": 8, "editedSlides": 9, "charts": 3, "embeddedWorkbooks": 3, "tables": 1,
          "notes": 9, "stylePartsRetained": len(style_parts),
          "stylePartsByteIdentical": sum(before[n] == after[n] for n in style_parts),
          "originalSHA256": hashlib.sha256((args.directory / "pptxgenjs.pptx").read_bytes()).hexdigest(),
          "independentZIPXML": "passed", "visualFidelity": "unverified"}
print(json.dumps(result, ensure_ascii=False))
