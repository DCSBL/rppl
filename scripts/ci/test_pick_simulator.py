import unittest

from pick_simulator import device_type, find_device, latest_runtime

DEVICES = {
    "com.apple.CoreSimulator.SimRuntime.iOS-18-6": [
        {"name": "iPhone SE (3rd generation)", "udid": "OLD", "isAvailable": True},
    ],
    "com.apple.CoreSimulator.SimRuntime.iOS-26-0": [
        {"name": "iPhone SE (3rd generation)", "udid": "NEW", "isAvailable": True},
        {"name": "iPhone 17", "udid": "GONE", "isAvailable": False},
    ],
}


class PickSimulatorTests(unittest.TestCase):
    def test_prefers_newest_runtime(self):
        self.assertEqual(find_device(DEVICES, "iPhone SE (3rd generation)"), "NEW")

    def test_ignores_unavailable_and_missing(self):
        self.assertIsNone(find_device(DEVICES, "iPhone 17"))
        self.assertIsNone(find_device(DEVICES, "iPhone 99"))

    def test_latest_runtime_compares_numerically(self):
        runtimes = [
            {"identifier": "ios9", "platform": "iOS", "version": "9.3", "isAvailable": True},
            {"identifier": "ios26", "platform": "iOS", "version": "26.0", "isAvailable": True},
            {"identifier": "watch", "platform": "watchOS", "version": "30.0", "isAvailable": True},
        ]
        self.assertEqual(latest_runtime(runtimes, "iOS"), "ios26")

    def test_unknown_device_type_exits(self):
        with self.assertRaises(SystemExit):
            device_type([{"name": "iPhone 17", "identifier": "x"}], "iPhone 99")


if __name__ == "__main__":
    unittest.main()
