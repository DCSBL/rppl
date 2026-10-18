import struct
import tempfile
import unittest
import zlib
from pathlib import Path

import check_marketing_assets as cma

CONFIG = """formats:
  phone: { w: 4, h: 6, folder: shots/phone }
  wide: { w: 8, h: 3, folder: header/wide }
defaults:
  formats: [phone, wide]
slides:
  - id: one
    text: "HI"
  - id: two
    formats: [phone]
"""


def png(w, h, color=2):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    ihdr = struct.pack(">IIBBBBB", w, h, 8, color, 0, 0, 0)
    return cma.PNG_SIG + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(b"\0")) + chunk(b"IEND", b"")


class CheckMarketingAssets(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.out = Path(self.tmp.name) / "out"
        self.config = Path(self.tmp.name) / "m.yaml"
        self.config.write_text(CONFIG)

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, rel, data):
        path = self.out / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def good(self):
        self.put("shots/phone/01-one.png", png(4, 6))
        self.put("header/wide/01-one.png", png(8, 3))
        self.put("shots/phone/02-two.png", png(4, 6))

    def test_parse_config(self):
        formats, slides = cma.parse_config(CONFIG)
        self.assertEqual(formats["wide"], (8, 3, "header/wide"))
        self.assertEqual(slides, [("one", ["phone", "wide"]), ("two", ["phone"])])

    def test_ok(self):
        self.good()
        self.assertEqual(cma.check(self.out, self.config), [])

    def test_missing_wrong_size_alpha_and_extra(self):
        self.put("shots/phone/01-one.png", png(5, 6))
        self.put("shots/phone/02-two.png", png(4, 6, color=6))
        self.put("stray.png", png(1, 1))
        errors = "\n".join(cma.check(self.out, self.config))
        self.assertIn("missing header/wide/01-one.png", errors)
        self.assertIn("5x6, want 4x6", errors)
        self.assertIn("alpha not allowed", errors)
        self.assertIn("unexpected stray.png", errors)


if __name__ == "__main__":
    unittest.main()
