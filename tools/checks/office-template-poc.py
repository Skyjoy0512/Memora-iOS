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

    # Independently validate the Swift run-spanning output without using its parser.
    original = zipfile.ZipFile(root / ('split-template.' + suffix))
    filled = zipfile.ZipFile(root / ('split-runs.' + suffix))
    assert original.namelist() == filled.namelist()
    for name in original.namelist():
        if name != target:
            assert original.read(name) == filled.read(name), name
        if name.endswith(('.xml', '.rels')):
            ET.fromstring(filled.read(name))
    old_tree = ET.fromstring(original.read(target))
    new_tree = ET.fromstring(filled.read(target))
    old_nodes, new_nodes = list(old_tree.iter()), list(new_tree.iter())
    assert len(old_nodes) == len(new_nodes)
    for old_node, new_node in zip(old_nodes, new_nodes):
        assert old_node.tag == new_node.tag
        assert {k: v for k, v in old_node.attrib.items() if k != '{http://www.w3.org/XML/1998/namespace}space'} == {k: v for k, v in new_node.attrib.items() if k != '{http://www.w3.org/XML/1998/namespace}space'}
        if not old_node.tag.endswith('}t'):
            assert old_node.text == new_node.text
    text = ''.join(n.text or '' for n in new_nodes if n.tag.endswith('}t'))
    assert '分割欄の日本語 & 検証' in text and '決定した内容 <編集可能>' in text
    assert '{{' not in text
    print(f'Split-run {suffix}: independent ZIP/XML reload, unchanged element/format attributes and untouched parts; Office layout unverified.')
