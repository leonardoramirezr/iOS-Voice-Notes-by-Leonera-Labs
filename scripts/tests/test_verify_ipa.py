import os
import plistlib
import tempfile
import unittest
import zipfile

import helpers  # noqa: F401
import verify_ipa

TEAM = "ABCDE12345"
BUNDLE = "com.example.app"


def profile_bytes(devices=("udid-1", "udid-2"), get_task_allow=False, all_devices=False, app_id=None, team=TEAM):
    profile = {
        "Name": "XC Ad Hoc: " + BUNDLE,
        "TeamIdentifier": [team],
        "ExpirationDate": "2027-01-01",
        "Entitlements": {"get-task-allow": get_task_allow, "application-identifier": app_id or f"{TEAM}.{BUNDLE}"},
    }
    if devices:
        profile["ProvisionedDevices"] = list(devices)
    if all_devices:
        profile["ProvisionsAllDevices"] = True
    # Real profiles are CMS envelopes around the XML plist; surround it with binary noise.
    return b"\x30\x82\x01\x02cms-header" + plistlib.dumps(profile) + b"\x00cms-signature"


def write_ipa(path, app_profile, extension=None):
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("Payload/App.app/Info.plist", plistlib.dumps({"CFBundleIdentifier": BUNDLE}))
        archive.writestr("Payload/App.app/embedded.mobileprovision", app_profile)
        archive.writestr("Payload/App.app/Frameworks/Simperium.framework/Info.plist", plistlib.dumps({}))
        if extension:
            identifier, profile = extension
            archive.writestr("Payload/App.app/PlugIns/Ext.appex/Info.plist",
                             plistlib.dumps({"CFBundleIdentifier": identifier}))
            if profile is not None:
                archive.writestr("Payload/App.app/PlugIns/Ext.appex/embedded.mobileprovision", profile)


class VerifyIpaTests(unittest.TestCase):
    def run_verify(self, app_profile, extension=None):
        with tempfile.TemporaryDirectory() as directory:
            ipa = os.path.join(directory, "App.ipa")
            write_ipa(ipa, app_profile, extension)
            return verify_ipa.main([ipa, "--team", TEAM, "--bundle-id", BUNDLE, "--skip-codesign"])

    def test_ad_hoc_profile_passes(self):
        self.assertEqual(self.run_verify(profile_bytes()), 0)

    def test_extension_with_profile_passes(self):
        extension_profile = profile_bytes(app_id=f"{TEAM}.{BUNDLE}.widget")
        self.assertEqual(self.run_verify(profile_bytes(), (BUNDLE + ".widget", extension_profile)), 0)

    def test_extension_without_profile_fails(self):
        self.assertEqual(self.run_verify(profile_bytes(), (BUNDLE + ".widget", None)), 1)

    def test_development_profile_fails(self):
        self.assertEqual(self.run_verify(profile_bytes(get_task_allow=True)), 1)

    def test_enterprise_profile_fails(self):
        self.assertEqual(self.run_verify(profile_bytes(devices=(), all_devices=True)), 1)

    def test_profile_without_devices_fails(self):
        self.assertEqual(self.run_verify(profile_bytes(devices=())), 1)

    def test_wrong_team_fails(self):
        self.assertEqual(self.run_verify(profile_bytes(team="OTHER")), 1)

    def test_wrong_bundle_fails(self):
        self.assertEqual(self.run_verify(profile_bytes(app_id=f"{TEAM}.com.other")), 1)

    def test_decode_profile_extracts_embedded_plist(self):
        with tempfile.NamedTemporaryFile(delete=False) as handle:
            handle.write(profile_bytes())
            path = handle.name
        try:
            self.assertEqual(len(verify_ipa.decode_profile(path)["ProvisionedDevices"]), 2)
        finally:
            os.remove(path)


if __name__ == "__main__":
    unittest.main()
