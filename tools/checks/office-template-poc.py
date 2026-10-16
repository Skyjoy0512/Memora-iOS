"""Independent local OOXML patch PoC; synthetic files only, no service/runtime in iOS."""
from pathlib import Path
import io
import copy
import sys
import zipfile
import xml.etree.ElementTree as ET

root = Path(sys.argv[1])
for suffix in ['docx', 'pptx']:
    source = root / ('generated.' + suffix)
    before = zipfile.ZipFile(source)
    target = 'word/document.xml' if suffix == 'docx' else 'ppt/slides/slide1.xml'
    output = io.BytesIO()
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for entry in before.infolist():
            value = before.read(entry.filename)
            if entry.filename == target:
                value = value.replace('日本語 &amp; 検証'.encode(), '独立PoCの日本語'.encode())
            archive.writestr(copy.copy(entry), value)
    after = zipfile.ZipFile(io.BytesIO(output.getvalue()))
    assert before.namelist() == after.namelist()
    for name in before.namelist():
        if name != target:
            assert before.read(name) == after.read(name), name
        if name.endswith(('.xml', '.rels')):
            ET.fromstring(after.read(name))
    assert '独立PoCの日本語'.encode() in after.read(target)
    (root / ('poc.' + suffix)).write_bytes(output.getvalue())
    print(f'Local OOXML PoC {suffix}: package/XML valid; all untouched parts byte-identical. Visual pagination unverified.')
