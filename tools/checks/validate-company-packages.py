"""Independent ZIP/XML checks of the synthetic corporate append outputs."""
import argparse
import hashlib
import json
import posixpath
from pathlib import Path
import xml.etree.ElementTree as ET
from zipfile import ZipFile

P = "{http://schemas.openxmlformats.org/presentationml/2006/main}"
A = "{http://schemas.openxmlformats.org/drawingml/2006/main}"
R = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
C = "{http://schemas.openxmlformats.org/package/2006/content-types}"


def parts(path):
    with ZipFile(path) as archive:
        assert len(set(archive.namelist())) == len(archive.namelist())
        return {name: archive.read(name) for name in archive.namelist()}


def validate(value, slide_count):
    for path, data in value.items():
        if path.endswith((".xml", ".rels")):
            tree = ET.fromstring(data)
            if path.endswith(".rels"):
                links = list(tree)
                assert len({link.get("Id") for link in links}) == len(links)
                base = posixpath.dirname(posixpath.dirname(path)) if path != "_rels/.rels" else ""
                for link in links:
                    assert link.get("TargetMode") not in ("External",)
                    target = link.attrib["Target"]
                    resolved = target.lstrip("/") if target.startswith("/") else posixpath.normpath(posixpath.join(base, target))
                    assert resolved in value, (path, target)
    presentation = ET.fromstring(value["ppt/presentation.xml"])
    ids = list(presentation.find(P + "sldIdLst"))
    assert len(ids) == slide_count and len({node.get("id") for node in ids}) == slide_count
    rels = {node.get("Id"): node.get("Target") for node in ET.fromstring(value["ppt/_rels/presentation.xml.rels"])}
    assert all(node.get(R + "id") in rels for node in ids)
    overrides = list(ET.fromstring(value["[Content_Types].xml"]).iter(C + "Override"))
    assert len({node.get("PartName") for node in overrides}) == len(overrides)
    assert all(node.attrib["PartName"].lstrip("/") in value for node in overrides)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    root = parser.parse_args().output
    original = parts(root / "source.pptx")
    central = {"ppt/presentation.xml", "ppt/_rels/presentation.xml.rels", "[Content_Types].xml"}
    names = [f"b{i:02}" for i in range(1, 31)] + [f"m{i:02}" for i in range(1, 36)]
    for name in names:
        result = parts(root / (name + ".pptx"))
        validate(result, 2)
        assert all(result[path] == data for path, data in original.items() if path not in central)
        slide = ET.fromstring(result["ppt/slides/slide2.xml"])
        assert slide.find(".//" + P + "sp") is not None and slide.find(".//" + P + "pic") is None
        text = "".join(node.text or "" for node in slide.iter(A + "t"))
        assert "記録を整理し、判断につなげる" in text
        ids = [node.get("id") for node in slide.iter(P + "cNvPr")]
        assert len(set(ids)) == len(ids)
        assert b"2563EB" not in result["ppt/slides/slide2.xml"] and b"F28C28" not in result["ppt/slides/slide2.xml"]
        notes = "".join(node.text or "" for node in ET.fromstring(result["ppt/notesSlides/notesSlide1.xml"]).iter(A + "t"))
        assert "ローカルfixture" in notes
        assert result["ppt/slides/_rels/slide2.xml.rels"].count(b"../slideLayouts/slideLayout1.xml") == 1
    validate(parts(root / "corporate-catalog.pptx"), 66)
    report = {"passed": len(names), "total": 65, "aggregatePages": 66,
              "checks": ["XML", "relationship targets", "content types", "unique IDs", "editable shapes", "Japanese", "sources", "original part bytes", "corporate layout link"],
              "sourceSHA256": hashlib.sha256((root / "source.pptx").read_bytes()).hexdigest(),
              "finalOfficeRendering": "unverified"}
    (root / "package-validation.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
