import unittest

from export_screenshots import attachment_name


class AttachmentNameTests(unittest.TestCase):
    def test_strips_xcode_suffix(self):
        suggested = "1-logbook_0_F16D4E6B-7933-4B65-B148-D2BD4AA95B19.png"
        self.assertEqual(attachment_name(suggested), "1-logbook")

    def test_keeps_plain_name(self):
        self.assertEqual(attachment_name("park.png"), "park.png")


if __name__ == "__main__":
    unittest.main()
