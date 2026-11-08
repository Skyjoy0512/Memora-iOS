"""Inspect each real exported package, including IDs, Japanese, vectors and notes."""
from pathlib import Path
import posixpath
import sys
import xml.etree.ElementTree as ET
import zipfile

root = Path(sys.argv[1])
ns = {"p": "http://schemas.openxmlformats.org/presentationml/2006/main",
      "a": "http://schemas.openxmlformats.org/drawingml/2006/main"}
files = sorted(p for p in root.glob("*.pptx") if p.stem != "catalog-65")
assert len(files) == 65, len(files)
for path in files:
    with zipfile.ZipFile(path) as z:
        assert not z.testzip()
        names = set(z.namelist())
        for name in names:
            if name.endswith((".xml", ".rels")):
                doc = ET.fromstring(z.read(name))
                if name.endswith(".rels"):
                    base = posixpath.dirname(posixpath.dirname(name))
                    for rel in doc:
                        if rel.attrib.get("TargetMode") != "External":
                            target = posixpath.normpath(posixpath.join(base, rel.attrib["Target"]))
                            assert target in names, (path.name, target)
        doc = ET.fromstring(z.read("ppt/slides/slide1.xml"))
        shapes = doc.findall(".//p:sp", ns)
        assert shapes and not doc.findall(".//p:pic", ns), path.name
        ids = [s.attrib["id"] for s in doc.findall(".//p:cNvPr", ns)]
        assert len(ids) == len(set(ids)), path.name
        assert "判断" in "".join(doc.itertext()), path.name
        # Static text-fit guard, independent of Office rendering: every text box
        # declares its pre-wrapped lines and no autofit, the declared line heights
        # fit the box, the box stays on the 960x540 page, and no run is tiny.
        for shape in shapes:
            text_body = shape.find("p:txBody", ns)
            if text_body is None:
                continue
            xfrm = shape.find("p:spPr/a:xfrm", ns)
            assert xfrm is not None, path.name
            off, ext = xfrm.find("a:off", ns), xfrm.find("a:ext", ns)
            assert off is not None and ext is not None, path.name
            x, y = int(off.attrib["x"]) / 12_700, int(off.attrib["y"]) / 12_700
            width, height = int(ext.attrib["cx"]) / 12_700, int(ext.attrib["cy"]) / 12_700
            assert -0.01 <= x and -0.01 <= y and x + width <= 960.01 and y + height <= 540.01, \
                (path.name, x, y, width, height)
            body_pr = text_body.find("a:bodyPr", ns)
            assert body_pr is not None and body_pr.attrib.get("wrap") == "none", path.name
            assert body_pr.find("a:noAutofit", ns) is not None, path.name
            total_line_points = 0.0
            for paragraph in text_body.findall("a:p", ns):
                spacing = paragraph.find("a:pPr/a:lnSpc/a:spcPts", ns)
                assert spacing is not None, path.name
                total_line_points += int(spacing.attrib["val"]) / 100
                for run in paragraph.findall("a:r", ns):
                    props = run.find("a:rPr", ns)
                    assert props is not None, path.name
                    assert int(props.attrib["sz"]) >= 800, (path.name, props.attrib["sz"])
            assert total_line_points <= height + 0.5, (path.name, total_line_points, height)
        notes = z.read("ppt/notesSlides/notesSlide1.xml").decode()
        assert "架空データ" in notes and "出典" in notes, path.name
        assert not any(n.startswith("ppt/media/") for n in names), path.name
        assert path.with_suffix(".pdf").stat().st_size > 1000
print("65/65 package XML, relationship targets, editable shapes, Japanese, sources, declared line fit/no tiny text and PDF presence passed")
