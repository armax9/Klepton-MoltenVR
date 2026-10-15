#!/usr/bin/env python3
"""Exercise the real project generator without game files or signing identities."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
GEN = ROOT / "visionos/gen_xcodeproj.py"


def generate(mode=None):
    env = dict(os.environ, KLEPTON_TARGET="beatsaber", KLEPTON_TEAM="TESTTEAM00",
               KLEPTON_BUNDLE_ID="example.existing.beatsaber", KLEPTON_START_SCREEN="1")
    env.pop("KLEPTON_CONTROLLER_MODE", None)
    if mode is not None:
        env["KLEPTON_CONTROLLER_MODE"] = mode
    # Importing builds exactly the PBX string main writes, without requiring guest dylibs.
    code = "import runpy,json,sys; sys.path.insert(0,%r); import targets; targets.libs_for=lambda _: 'libsynthetic'; m=runpy.run_path(%r); print(json.dumps({'pbx':m['PBX'],'swift':m['SWIFT'],'privacy':m['USAGE_DESCRIPTIONS'],'entitlements':m['ENTITLEMENTS_FILE']}))" % (str(GEN.parent), str(GEN))
    result = subprocess.run([sys.executable, "-c", code], env=env, cwd=ROOT, capture_output=True, text=True)
    if result.returncode:
        raise ValueError(result.stderr)
    return json.loads(result.stdout)


class ProjectTests(unittest.TestCase):
    def test_modes_include_both_backends_and_keep_signing_identity(self):
        standard = generate()
        surreal = generate("surreal")
        self.assertIn('KL_CONTROLLER_MODE_DEFAULT = "standard";', standard["pbx"])
        self.assertIn('KL_CONTROLLER_MODE_DEFAULT = "surreal";', surreal["pbx"])
        self.assertEqual(standard["swift"], surreal["swift"])
        for name in ["KleptonControllers.swift", "KleptonControllerInput.swift", "KleptonControllerMode.swift",
                     "KleptonSurrealInput.swift", "KleptonSurrealBackend.swift", "KleptonSurrealView.swift",
                     "KleptonSurrealAim.swift", "KleptonSurrealAimView.swift"]:
            self.assertIn(name, surreal["swift"])
            self.assertTrue((ROOT / "visionos/Sources" / name).is_file())
        # Only the default changes: identity, entitlements, signing flags and framework list stay identical.
        self.assertEqual(standard["pbx"], surreal["pbx"].replace('KL_CONTROLLER_MODE_DEFAULT = "surreal";', 'KL_CONTROLLER_MODE_DEFAULT = "standard";'))
        self.assertIn("example.existing.beatsaber", surreal["pbx"])
        self.assertNotIn("OpenSurreal", surreal["pbx"])

    def test_privacy_survives_generator_and_plist(self):
        generated = generate("surreal")
        info = plistlib.loads((ROOT / "visionos/Info.plist").read_bytes())
        self.assertEqual(info["KLControllerModeDefault"], "$(KL_CONTROLLER_MODE_DEFAULT)")
        for key in ["NSBluetoothAlwaysUsageDescription", "NSHandsTrackingUsageDescription", "NSWorldSensingUsageDescription"]:
            self.assertTrue(info[key])
            self.assertTrue(generated["privacy"][key])
            self.assertIn("INFOPLIST_KEY_" + key, generated["pbx"])

    def test_rejects_invalid_configuration(self):
        for value in ["unknown", 'surreal"; OTHER = 1;', ""]:
            with self.assertRaises(ValueError):
                generate(value)


if __name__ == "__main__":
    unittest.main()
