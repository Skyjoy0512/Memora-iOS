"""Checks the supplied vector pair; runtime layout is covered by sidebar-glass.e2e.ts."""
import json
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "App/Assets.xcassets/memora-sidebar-logo.imageset"


class SidebarBrandAssetChecks(unittest.TestCase):
    def test_original_vector_pair_has_matching_geometry(self):
        light = ET.parse(ASSETS / "memora-logo-sidebar.svg").getroot()
        dark = ET.parse(ASSETS / "memora-logo-sidebar-dark.svg").getroot()
        for svg, color in ((light, "#0B0B0B"), (dark, "#FAF9F3")):
            self.assertEqual(svg.attrib["viewBox"], "0.5 0 88 18")
            self.assertEqual((svg.attrib["width"], svg.attrib["height"]), ("132", "27"))
            self.assertEqual(svg[1].attrib["fill"], color)
            self.assertEqual(len(svg[1]), 5)
        self.assertEqual(
            [(shape.tag, shape.attrib) for shape in light[1]],
            [(shape.tag, shape.attrib) for shape in dark[1]],
        )

    def test_asset_catalog_switches_appearance_without_tinting(self):
        contents = json.loads((ASSETS / "Contents.json").read_text())
        self.assertTrue(contents["properties"]["preserves-vector-representation"])
        self.assertEqual(contents["properties"]["template-rendering-intent"], "original")
        images = contents["images"]
        self.assertEqual(len(images), 2)
        self.assertEqual(images[0]["filename"], "memora-logo-sidebar.svg")
        self.assertEqual(images[1]["filename"], "memora-logo-sidebar-dark.svg")
        self.assertEqual(images[1]["appearances"], [{"appearance": "luminosity", "value": "dark"}])


if __name__ == "__main__":
    unittest.main()
