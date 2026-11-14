"""Guard the approved v3 brand artwork and the AppIcon inputs.

Run: python3 -B tools/checks/test_sidebar_brand_assets.py
"""
import hashlib
import json
import struct
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "App/Assets.xcassets"
BRAND = ROOT / "docs/brand/memora-geometric-v3"
APP_SOURCES = [ROOT / "App", ROOT / "Shared"]

# SHA-256 of the supplied v3 SVG set, independent of our rendering.
ORIGINALS = {
    "memora-geometric-v3-mark-light.svg": "4f6401c5273f5ee5f34a4f1019d8bcab7dd54b1bc8be85b76744088e3adc93a7",
    "memora-geometric-v3-mark-dark.svg": "c74b93b51afb4ffe7e902bcf5b5209e0e7e0f5b67f774c8f6c79be0a6c64c09f",
    "memora-geometric-v3-mark-adaptive.svg": "74f3fc7f0bfaba2279b02bd4fa63d4d585f8dbf031cd4add981070722838363b",
    "memora-geometric-v3-lockup-light.svg": "51b06abe61a01a452e52ddf5472f5d8965fa3753405650c338eb98cade7a28fa",
    "memora-geometric-v3-lockup-dark.svg": "f30980d008761cef6fc782c1a7fa68861362a7f1c2c56bca4d96e50b920fc9a7",
    "memora-geometric-v3-lockup-adaptive.svg": "b3a1f30ee0aaecb2ce88b8caedae79fe1289c15621854a0f938af8d55871f3e7",
}


class BrandAssetChecks(unittest.TestCase):
    def test_supplied_artwork_is_byte_identical(self):
        for name, digest in ORIGINALS.items():
            with self.subTest(name=name):
                self.assertEqual(hashlib.sha256((BRAND / name).read_bytes()).hexdigest(), digest)

    def test_icon_appearance_inputs_are_full_size_and_opaque(self):
        folder = ASSETS / "AppIcon.appiconset"
        contents = json.loads((folder / "Contents.json").read_text())
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

    def test_old_logo_artwork_and_references_are_gone(self):
        for name in ("memora-wordmark.imageset", "memora-symbol.imageset",
                     "memora-sidebar-logo.imageset"):
            self.assertFalse((ASSETS / name).exists(), name)
        for source in APP_SOURCES:
            for file in source.rglob("*.swift"):
                text = file.read_text()
                for old in ("memora-symbol", "memora-wordmark", "MemoraSymbol"):
                    self.assertNotIn(old, text, f"{file}: {old}")

    def test_mark_solids_and_wordmark_strokes_are_defined(self):
        geometry = (ROOT / "App/MemoraBrandShape.swift").read_text()
        for shape in ("record", "organize", "understand", "connect", "expand"):
            self.assertIn(f"case {shape}", geometry)
        # The center is a true circle in the supplied 432x92 space.
        self.assertIn("CGRect(x: 144, y: 0, width: 92, height: 92)", geometry)
        wordmark = (ROOT / "App/MemoraBrandGeometry.swift").read_text()
        self.assertIn("wordmarkStrokeWidth: CGFloat = 1.65", wordmark)
        self.assertIn("width: 19, height: 19", wordmark)


if __name__ == "__main__":
    unittest.main()
