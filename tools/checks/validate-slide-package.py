"""Inspect generated OOXML independently of the Swift writer/parser; no network."""
import json
from pathlib import Path
import posixpath
import sys
import xml.etree.ElementTree as ET
import zipfile

root = Path(sys.argv[1])
ns = {"a": "http://schemas.openxmlformats.org/drawingml/2006/main",
      "p": "http://schemas.openxmlformats.org/presentationml/2006/main",
      "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships"}
package_ns = "http://schemas.openxmlformats.org/package/2006/relationships"
expected = json.loads((root / "pages.json").read_text())
with zipfile.ZipFile(root / "pagination.pptx") as archive:
    assert archive.testzip() is None
    names = archive.namelist()
    assert len(names) == len(set(names)), "duplicate ZIP part"
    for name in names:
        assert not name.startswith("/") and ".." not in name.split("/")
        if name.endswith((".xml", ".rels")):
            ET.fromstring(archive.read(name))
        if name.endswith(".rels"):
            owner = posixpath.dirname(posixpath.dirname(name))
            relationships = ET.fromstring(archive.read(name))
            ids = [r.attrib["Id"] for r in relationships]
            assert len(ids) == len(set(ids))
            for relationship in relationships:
                assert relationship.tag == "{" + package_ns + "}Relationship"
                assert relationship.attrib.get("TargetMode") != "External"
                target = posixpath.normpath(posixpath.join(owner, relationship.attrib["Target"]))
                assert target in names, (name, target)

    presentation = ET.fromstring(archive.read("ppt/presentation.xml"))
    assert len(presentation.findall("p:sldIdLst/p:sldId", ns)) == len(expected)
    types = ET.fromstring(archive.read("[Content_Types].xml"))
    overrides = {node.attrib["PartName"].lstrip("/"): node.attrib["ContentType"]
                 for node in types if node.tag.endswith("}Override")}
    assert all(name in names for name in overrides)
    note_count = 0
    size = presentation.find("p:sldSz", ns)
    width, height = int(size.attrib["cx"]), int(size.attrib["cy"])
    for number, page in enumerate(expected, 1):
        tree = ET.fromstring(archive.read(f"ppt/slides/slide{number}.xml"))
        shapes = tree.findall("p:cSld/p:spTree/p:sp", ns)
        assert shapes, "editable text shapes required"
        title = [t.text or "" for t in shapes[0].findall(".//a:t", ns)]
        points = [t.text or "" for shape in shapes[1:] for t in shape.findall(".//a:t", ns)]
        assert title == page["title"], (number, "title text")
        assert points == page["bullets"], (number, "body text")
        assert not tree.findall(".//p:pic", ns), "text must remain editable"
        note_name = f"ppt/notesSlides/notesSlide{number}.xml"
        rels = ET.fromstring(archive.read(f"ppt/slides/_rels/slide{number}.xml.rels"))
        notes_relationships = [r for r in rels if r.attrib["Type"].endswith("/notesSlide")]
        if page["notes"]:
            note_count += 1
            assert len(notes_relationships) == 1
            assert notes_relationships[0].attrib["Target"] == f"../notesSlides/notesSlide{number}.xml"
            assert overrides[note_name].endswith(".notesSlide+xml")
            note = ET.fromstring(archive.read(note_name))
            assert note.find(".//p:ph[@type='body']", ns) is not None
            paragraphs = note.findall("p:cSld/p:spTree/p:sp/p:txBody/a:p", ns)
            assert ["".join(t.text or "" for t in p.findall(".//a:t", ns)) for p in paragraphs] == page["notes"]
            note_rels = ET.fromstring(archive.read(f"ppt/notesSlides/_rels/notesSlide{number}.xml.rels"))
            assert any(r.attrib["Type"].endswith("/slide") and
                       r.attrib["Target"] == f"../slides/slide{number}.xml" for r in note_rels)
        else:
            assert note_name not in names and not notes_relationships
        previous_bottom = 0
        for shape in shapes:
            transform = shape.find("p:spPr/a:xfrm", ns)
            off, extent = transform.find("a:off", ns), transform.find("a:ext", ns)
            x, y = int(off.attrib["x"]), int(off.attrib["y"])
            w, h = int(extent.attrib["cx"]), int(extent.attrib["cy"])
            assert 0 <= x < width and 0 <= y < height and w > 0 and h > 0
            assert x + w <= width and y + h <= height
            assert y >= previous_bottom, "overlapping text frames"
            previous_bottom = y + h
            for run in shape.findall(".//a:rPr", ns):
                assert int(run.attrib["sz"]) >= 2400
            assert shape.find("p:txBody/a:bodyPr/a:noAutofit", ns) is not None
    assert note_count == len([n for n in names if n.startswith("ppt/notesSlides/notesSlide") and n.endswith(".xml")])
    assert presentation.find("p:notesMasterIdLst/p:notesMasterId", ns) is not None
    assert overrides["ppt/notesMasters/notesMaster1.xml"].endswith(".notesMaster+xml")
    print(f"Slide package: passed ({len(expected)} pages, {note_count} notes; independent ZIP/XML, all relationship targets, ordered editable text, notes and frame bounds; Office rendering unverified)")

with zipfile.ZipFile(root / "controls.pptx") as archive:
    for name in archive.namelist():
        if name.endswith((".xml", ".rels")):
            ET.fromstring(archive.read(name))
    assert "前後" in archive.read("ppt/slides/slide1.xml").decode()
    assert "注記" in archive.read("ppt/notesSlides/notesSlide1.xml").decode()
    print("Slide XML: passed (forbidden XML scalars excluded from headings, body and notes)")
