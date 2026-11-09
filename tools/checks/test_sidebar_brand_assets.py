"""Guard canonical brand artwork; verify runtime presentation in the simulator."""
import hashlib
import json
from pathlib import Path
import struct
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "App/Assets.xcassets"
# SHA-256 of the supplied ZIP entries, independent of our asset catalog.
ORIGINALS = {
    "AppIcon.appiconset/memora-appicon-light.png": "4fb5d12cebaad0ad56c95d2e562d90a472e65ee640d044d9ec1127e99e757910",
    "AppIcon.appiconset/memora-appicon-dark.png": "9d5f9fb74313fa10229bc268c66eeda5fe3e20d819229cd0062ed17b59a37371",
    "memora-wordmark.imageset/memora-wordmark-light.svg": "c76b726e3156a395a644762a16a3a4d4ca103b8ad2049e363fcd62f6c34b8dd3",
    "memora-wordmark.imageset/memora-wordmark-dark.svg": "ce247b37b5527896ee7e3fa39442781a49da27d6089ed032e0f88a12ec348a99",
    "memora-symbol.imageset/memora-symbol-light.svg": "afcdbbcbcaf9258871d72de08368253f709d208165f08a1e26ecda5588174ccc",
    "memora-symbol.imageset/memora-symbol-dark.svg": "c60c32f22712223fecd3de113122e4559cdc4664f4173d4250f01d98479fea55",
}


class SidebarBrandAssetChecks(unittest.TestCase):
    def test_supplied_artwork_is_byte_identical(self):
        for path, digest in ORIGINALS.items():
            with self.subTest(path=path):
                self.assertEqual(hashlib.sha256((ASSETS / path).read_bytes()).hexdigest(), digest)

    def test_vector_pairs_keep_geometry_and_select_original_colors(self):
        for role in ("wordmark", "symbol"):
            folder = ASSETS / f"memora-{role}.imageset"
            contents = json.loads((folder / "Contents.json").read_text())
            self.assertTrue(contents["properties"]["preserves-vector-representation"])
            self.assertEqual(contents["properties"]["template-rendering-intent"], "original")
            light, dark = contents["images"]
            self.assertNotIn("appearances", light)
            self.assertEqual(dark["appearances"], [{"appearance": "luminosity", "value": "dark"}])
            a = ET.parse(folder / light["filename"]).getroot()
            b = ET.parse(folder / dark["filename"]).getroot()
            self.assertEqual(a.attrib, b.attrib)
            paths = lambda svg: [p.attrib for p in svg.iter("{http://www.w3.org/2000/svg}path")]
            # Only the explicit stroke color differs between appearances.
            clean = lambda svg: [{k: v for k, v in p.items() if k != "stroke"} for p in paths(svg)]
            self.assertEqual(clean(a), clean(b))

    def test_icon_appearance_inputs_are_full_size_and_opaque(self):
        folder = ASSETS / "AppIcon.appiconset"
        contents = json.loads((folder / "Contents.json").read_text())
        self.assertEqual(len(contents["images"]), 3)
        appearances = set()
        for image in contents["images"]:
            variant = image.get("appearances", [{"value": "light"}])[0]["value"]
            appearances.add(variant)
            data = (folder / image["filename"]).read_bytes()
            self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
            width, height, depth, color = struct.unpack(">IIBB", data[16:26])
            self.assertEqual((width, height, depth), (1024, 1024, 8))
            # PNG 0 is grayscale; 2 is RGB. Neither has an alpha channel.
            self.assertEqual(color, 0 if variant == "tinted" else 2)
            self.assertNotIn(b"tRNS", data)
        self.assertEqual(appearances, {"light", "dark", "tinted"})


if __name__ == "__main__":
    unittest.main()
