import datetime
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from build_parks_distribution import build

NOW = datetime.datetime(2026, 10, 22, 12, 41, tzinfo=datetime.timezone.utc)


class BuildParksDistributionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.parks = self.tmp / "parks"
        self.parks.mkdir()
        (self.parks / "a.yaml").write_text("version: 1\nid: a\nname: A\n")
        (self.parks / "b.yaml").write_text("version: 1\nid: b\nname: B\n")
        self.out = self.tmp / "out"

    def manifest(self):
        return json.loads((self.out / "manifest.json").read_text())

    def test_first_build_writes_manifest_and_files(self):
        self.assertTrue(build(self.parks, self.out, None, NOW))
        m = self.manifest()
        self.assertEqual(m["dataVersion"], 1)
        self.assertEqual(m["publishedAt"], "2026-10-22T12:41:00Z")
        self.assertTrue(m["enabled"])
        self.assertEqual((m["minAppSchema"], m["maxAppSchema"]), (1, 1))
        a = m["parks"][0]
        self.assertEqual(a["file"], "a.yaml")
        self.assertEqual(a["sha256"], hashlib.sha256((self.parks / "a.yaml").read_bytes()).hexdigest())
        self.assertEqual((self.out / "a.yaml").read_bytes(), (self.parks / "a.yaml").read_bytes())

    def test_unchanged_parks_write_nothing(self):
        build(self.parks, self.out, None, NOW)
        previous = self.manifest()
        fresh = self.tmp / "fresh"
        self.assertFalse(build(self.parks, fresh, previous, NOW))
        self.assertFalse(fresh.exists())

    def test_change_bumps_version_and_keeps_kill_switch(self):
        build(self.parks, self.out, None, NOW)
        previous = self.manifest()
        previous["enabled"] = False
        (self.parks / "a.yaml").write_text("version: 1\nid: a\nname: A2\n")
        self.assertTrue(build(self.parks, self.out, previous, NOW))
        m = self.manifest()
        self.assertEqual(m["dataVersion"], 2)
        self.assertFalse(m["enabled"])


if __name__ == "__main__":
    unittest.main()
