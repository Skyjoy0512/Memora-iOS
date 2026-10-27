"""Inspect each real exported package, including IDs, Japanese, vectors and notes."""
from pathlib import Path
import posixpath
import sys
import xml.etree.ElementTree as ET
import zipfile

root = Path(sys.argv[1])
ns = {"p": "http://schemas.openxmlformats.org/presentationml/2006/main",
      "a": "http://schemas.openxmlformats.org/drawingml/2006/main"}
files = sorted(root.glob("*.pptx"))
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
        notes = z.read("ppt/notesSlides/notesSlide1.xml").decode()
        assert "架空データ" in notes and "出典" in notes, path.name
        assert not any(n.startswith("ppt/media/") for n in names), path.name
        assert path.with_suffix(".pdf").stat().st_size > 1000
print("65/65 package XML, relationship targets, editable shapes, Japanese, sources and PDF presence passed")
