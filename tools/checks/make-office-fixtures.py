"""Local, synthetic packages only; no user documents or network access."""
import io
import pathlib
import struct
import sys
import warnings
import zipfile

root = pathlib.Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)
rels_ns = 'http://schemas.openxmlformats.org/package/2006/relationships'
rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
word = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
sheet = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
drawing = 'http://schemas.openxmlformats.org/drawingml/2006/main'
presentation = 'http://schemas.openxmlformats.org/presentationml/2006/main'


def relationships(items):
    return f'<Relationships xmlns="{rels_ns}">' + ''.join(items) + '</Relationships>'


def relationship(key, kind, target, external=False):
    mode = ' TargetMode="External"' if external else ''
    return f'<Relationship Id="{key}" Type="{rel}/{kind}" Target="{target}"{mode}/>'


def package(part, mime):
    return {
        '_rels/.rels': relationships([relationship('root', 'officeDocument', part)]),
        '[Content_Types].xml': '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        f'<Override PartName="/{part}" ContentType="application/vnd.openxmlformats-officedocument.{mime}.main+xml"/></Types>',
    }


def save(name, parts, compression=zipfile.ZIP_DEFLATED):
    with zipfile.ZipFile(root / name, 'w', compression=compression) as archive:
        for path, value in parts.items():
            archive.writestr(path, value)


doc = package('word/document.xml', 'wordprocessingml.document')
doc['word/document.xml'] = f'<w:document xmlns:w="{word}"><w:body>' \
    '<w:p><w:r><w:t>会議の決定 &amp; 次の仕事</w:t><w:tab/><w:t>Alpha</w:t><w:br/><w:t>Beta</w:t></w:r></w:p>' \
    '<w:del><w:p><w:r><w:t>DELETED TEXT</w:t></w:r></w:p></w:del>' \
    '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>担当: Ken</w:t></w:r></w:p></w:tc></w:tr></w:tbl>' \
    '</w:body></w:document>'
save('valid.docx', doc)
save('stored.docx', doc, zipfile.ZIP_STORED)
strict = {key: value.replace(word, 'http://purl.oclc.org/ooxml/wordprocessingml/main')
          .replace(rel, 'http://purl.oclc.org/ooxml/officeDocument/relationships') for key, value in doc.items()}
save('strict.docx', strict)

ppt = package('ppt/presentation.xml', 'presentationml.presentation')
ppt['ppt/presentation.xml'] = f'<p:presentation xmlns:p="{presentation}" xmlns:r="{rel}"><p:sldIdLst>' \
    '<p:sldId id="301" r:id="second"/><p:sldId id="300" r:id="first"/></p:sldIdLst></p:presentation>'
ppt['ppt/_rels/presentation.xml.rels'] = relationships([
    relationship('first', 'slide', 'slides/slide1.xml'), relationship('second', 'slide', 'slides/slide2.xml')])
for index in [1, 2]:
    ppt[f'ppt/slides/slide{index}.xml'] = f'<p:sld xmlns:p="{presentation}" xmlns:a="{drawing}">' \
        f'<p:cSld><p:spTree><a:p><a:r><a:t>CONTENT {index}</a:t></a:r></a:p></p:spTree></p:cSld></p:sld>'
save('ordered.pptx', ppt)

xls = package('xl/workbook.xml', 'spreadsheetml.sheet')
xls['xl/workbook.xml'] = f'<workbook xmlns="{sheet}" xmlns:r="{rel}"><sheets>' \
    '<sheet name="今月" sheetId="1" r:id="second"/><sheet name="先月" sheetId="2" r:id="first"/>' \
    '<sheet name="非表示" sheetId="3" state="hidden" r:id="hidden"/></sheets></workbook>'
xls['xl/_rels/workbook.xml.rels'] = relationships([
    relationship('first', 'worksheet', 'worksheets/sheet1.xml'),
    relationship('second', 'worksheet', 'worksheets/sheet2.xml'),
    relationship('hidden', 'worksheet', 'worksheets/hidden.xml'),
    relationship('strings', 'sharedStrings', 'sharedStrings.xml')])
xls['xl/sharedStrings.xml'] = f'<sst xmlns="{sheet}"><si><r><t>Budget</t></r><r><t> 2026</t></r>' \
    '<rPh><t>PHONETIC MUST NOT BE COPIED</t></rPh></si></sst>'
xls['xl/worksheets/sheet1.xml'] = f'<worksheet xmlns="{sheet}"><sheetData><row r="1">' \
    '<c r="A1" t="s"><v>0</v></c><c r="B1" t="b"><v>1</v></c>' \
    '<c r="C1"><f>SUM(40,2)</f><v>42</v></c><c r="D1"><f>NOT_EVALUATED()</f></c>' \
    '</row></sheetData></worksheet>'
xls['xl/worksheets/sheet2.xml'] = f'<worksheet xmlns="{sheet}"><sheetData><row r="1">' \
    '<c r="A1" t="inlineStr"><is><t>今月の売上</t></is></c><c r="B1"><v>1200</v></c>' \
    '</row></sheetData></worksheet>'
xls['xl/worksheets/hidden.xml'] = 'NOT XML AND MUST NOT BE OPENED'
save('ordered.xlsx', xls)

bad = dict(doc)
bad['../escape.txt'] = 'must never be extracted'
save('traversal.docx', bad)
bad = dict(doc)
bad['word/document.xml'] = '<!DOCTYPE x [<!ENTITY steal SYSTEM "file:///etc/hosts">]>' + doc['word/document.xml']
save('entity.docx', bad)
bad['word/document.xml'] = bad['word/document.xml'].encode('utf-16')
save('utf16-entity.docx', bad)
bad = dict(doc)
bad['word/document.xml'] = '<w:document xmlns:w="' + word + '"><w:body>' + '<w:p>' * 50 + 'text' + '</w:p>' * 50 + '</w:body></w:document>'
save('depth.docx', bad)
bad['word/document.xml'] = f'<w:document xmlns:w="{word}"><w:body>' + '<w:p><w:r><w:t>a</w:t></w:r></w:p>' * 10_001 + '</w:body></w:document>'
save('nodes.docx', bad)
bad['word/document.xml'] = f'<w:document xmlns:w="{word}"><w:body><w:p><w:r><w:t>' + 'x' * 80_010 + '</w:t></w:r></w:p></w:body></w:document>'
save('text-limit.docx', bad)
bad['word/document.xml'] = f'<w:document xmlns:w="{word}"><w:body><w:p><w:r><w:t>A' + '\u0301' * 500_000 + '</w:t></w:r></w:p></w:body></w:document>'
save('unicode-byte-limit.docx', bad)
bad['word/document.xml'] = 'x' * (2 * 1024 * 1024 + 1)
save('part-bomb.docx', bad)
bad = dict(doc)
bad['_rels/.rels'] = relationships([relationship('root', 'officeDocument', 'https://example.com/private', True)])
save('external.docx', bad)
bad['_rels/.rels'] = relationships([relationship('root', 'officeDocument', '../../outside.xml')])
save('relationship-escape.docx', bad)
bad = dict(doc)
bad.pop('word/document.xml')
save('missing.docx', bad)
bad = dict(doc)
bad['[Content_Types].xml'] = bad['[Content_Types].xml'].replace('application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml', 'application/vnd.ms-word.document.macroEnabled.main+xml')
save('macro.docx', bad)
bad = dict(xls)
bad['xl/worksheets/sheet1.xml'] = bad['xl/worksheets/sheet1.xml'].replace('<v>0</v>', '<v>99</v>')
save('bad-string-index.xlsx', bad)
bad = dict(ppt)
bad['ppt/_rels/presentation.xml.rels'] = relationships([relationship('second', 'slide', 'https://example.com/slide', True)])
save('external-slide.pptx', bad)

original = (root / 'stored.docx').read_bytes()
corrupt = original.replace('担当: Ken'.encode(), b'X' * len('担当: Ken'.encode()), 1)
(root / 'crc.docx').write_bytes(corrupt)
(root / 'truncated.docx').write_bytes(original[:-10])
encrypted = bytearray(original)
for signature, flags_offset in [(b'PK\x03\x04', 6), (b'PK\x01\x02', 8)]:
    at = 0
    while (at := encrypted.find(signature, at)) >= 0:
        flags = struct.unpack_from('<H', encrypted, at + flags_offset)[0]
        struct.pack_into('<H', encrypted, at + flags_offset, flags | 1)
        at += 4
(root / 'encrypted.docx').write_bytes(encrypted)
with zipfile.ZipFile(root / 'symlink.docx', 'w') as archive:
    for path, value in doc.items():
        archive.writestr(path, value)
    info = zipfile.ZipInfo('word/symlink')
    info.create_system = 3
    info.external_attr = 0o120777 << 16
    archive.writestr(info, '/private')
with warnings.catch_warnings():
    warnings.simplefilter('ignore', UserWarning)
    with zipfile.ZipFile(root / 'duplicate.docx', 'w') as archive:
        for path, value in doc.items():
            archive.writestr(path, value)
        archive.writestr('word/document.xml', 'duplicate')

# A non-seekable writer produces standard ZIP data descriptors.
class StreamingBuffer(io.BytesIO):
    def seekable(self):
        return False

    def seek(self, *args):
        raise io.UnsupportedOperation('non-seekable fixture')


buffer = StreamingBuffer()
with zipfile.ZipFile(buffer, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
    for path, value in doc.items():
        archive.writestr(path, value)
(root / 'descriptor.docx').write_bytes(buffer.getvalue())
