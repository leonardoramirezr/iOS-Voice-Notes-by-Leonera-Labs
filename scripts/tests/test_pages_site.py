import json
import os
import plistlib
import tempfile
import unittest

import helpers  # noqa: F401
import pages_site

BASE = "https://leonardoramirezr.github.io/iOS-Voice-Notes-by-Leonera-Labs"


class Args:
    def __init__(self, site, files, **overrides):
        self.site = site
        self.base_url = BASE
        self.tag = "build-1-abcdef1"
        self.channel = "branch"
        self.ipa = files["ipa"]
        self.icon57 = files["icon57"]
        self.icon512 = files["icon512"]
        self.title = "Voice Notes by Leonera Labs"
        self.bundle_id = "com.leonardoramirezr.voicenotesbyleoneralabs"
        self.version = "0.0.0"
        self.build_number = "1"
        self.branch = "dev"
        self.sha = "abcdef1234567890"
        self.repo = "leonardoramirezr/iOS-Voice-Notes-by-Leonera-Labs"
        self.run_id = "99"
        self.run_number = "1"
        self.devices = "2"
        self.created_at = "2026-10-21T10:00:00Z"
        self.keep_branch_builds = 20
        for key, value in overrides.items():
            setattr(self, key, value)


class PagesSiteTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        root = self.directory.name
        self.site = os.path.join(root, "site")
        self.files = {}
        for name in ("ipa", "icon57", "icon512"):
            path = os.path.join(root, name)
            with open(path, "wb") as handle:
                handle.write(name.encode())
            self.files[name] = path

    def tearDown(self):
        self.directory.cleanup()

    def add(self, **overrides):
        return pages_site.add_build(Args(self.site, self.files, **overrides))

    def test_urls_are_absolute_and_encoded(self):
        urls = pages_site.build_urls(BASE, "0.1.0")
        self.assertEqual(urls["page_url"], BASE + "/0.1.0/")
        self.assertEqual(urls["manifest_url"], BASE + "/0.1.0/manifest.plist")
        self.assertEqual(
            urls["install_url"],
            "itms-services://?action=download-manifest&url="
            "https%3A%2F%2Fleonardoramirezr.github.io%2FiOS-Voice-Notes-by-Leonera-Labs%2F0.1.0%2Fmanifest.plist",
        )

    def test_build_folder_contents(self):
        self.add()
        folder = os.path.join(self.site, "build-1-abcdef1")
        self.assertEqual(sorted(os.listdir(folder)),
                         ["VoiceNotes.ipa", "build.json", "icon-512.png", "icon-57.png", "index.html", "manifest.plist"])
        with open(os.path.join(folder, "manifest.plist"), "rb") as handle:
            manifest = plistlib.load(handle)
        item = manifest["items"][0]
        kinds = {asset["kind"]: asset["url"] for asset in item["assets"]}
        self.assertEqual(kinds["software-package"], BASE + "/build-1-abcdef1/VoiceNotes.ipa")
        self.assertEqual(kinds["display-image"], BASE + "/build-1-abcdef1/icon-57.png")
        self.assertEqual(kinds["full-size-image"], BASE + "/build-1-abcdef1/icon-512.png")
        self.assertEqual(item["metadata"]["bundle-identifier"], "com.leonardoramirezr.voicenotesbyleoneralabs")
        with open(os.path.join(folder, "index.html")) as handle:
            page = handle.read()
        self.assertIn('href="itms-services://?action=download-manifest&amp;url=https%3A%2F%2F', page)
        with open(os.path.join(folder, "build.json")) as handle:
            self.assertEqual(json.load(handle)["channel"], "branch")
        self.assertTrue(os.path.exists(os.path.join(self.site, ".nojekyll")))

    def test_foreign_entries_are_removed(self):
        os.makedirs(os.path.join(self.site, "App"))
        os.makedirs(os.path.join(self.site, "old-folder"))
        with open(os.path.join(self.site, "README.md"), "w") as handle:
            handle.write("source code")
        with open(os.path.join(self.site, ".gitignore"), "w") as handle:
            handle.write("*.ipa\n")
        self.add()
        self.assertEqual(sorted(os.listdir(self.site)), [".nojekyll", "build-1-abcdef1", "index.html"])

    def test_root_index_offers_latest_stable(self):
        self.add(tag="0.1.0", channel="stable", version="0.1.0", created_at="2026-10-20T10:00:00Z")
        self.add(tag="0.2.0", channel="stable", version="0.2.0", created_at="2026-10-21T09:00:00Z")
        self.add(tag="build-9-1111111", created_at="2026-10-21T11:00:00Z")
        with open(os.path.join(self.site, "index.html")) as handle:
            index = handle.read()
        self.assertIn("Install latest stable", index)
        latest = index.index("Latest stable version")
        self.assertIn("0.2.0", index[latest:latest + 200])
        self.assertIn(pages_site.build_urls(BASE, "0.2.0")["install_url"].replace("&", "&amp;"), index)
        for tag in ("0.1.0", "0.2.0", "build-9-1111111"):
            self.assertIn(tag, index)

    def test_root_index_without_stable(self):
        self.add()
        with open(os.path.join(self.site, "index.html")) as handle:
            self.assertIn("No stable version", handle.read())

    def test_keeps_all_stable_and_newest_branch_builds(self):
        for number in range(1, 4):
            self.add(tag=f"0.{number}.0", channel="stable", version=f"0.{number}.0",
                     created_at=f"2026-10-0{number}T00:00:00Z", run_number=str(number))
        for number in range(10, 33):
            self.add(tag=f"build-{number}-abcdef1", run_number=str(number),
                     created_at=f"2026-10-21T10:{number:02d}:00Z")
        names = sorted(name for name in os.listdir(self.site) if not name.startswith(".") and name != "index.html")
        branch = [name for name in names if name.startswith("build-")]
        self.assertEqual(len(branch), 20)
        self.assertNotIn("build-10-abcdef1", branch)
        self.assertIn("build-32-abcdef1", branch)
        self.assertEqual([name for name in names if not name.startswith("build-")], ["0.1.0", "0.2.0", "0.3.0"])

    def test_republishing_a_tag_replaces_it(self):
        self.add(devices="1")
        self.add(devices="3")
        with open(os.path.join(self.site, "build-1-abcdef1", "build.json")) as handle:
            self.assertEqual(json.load(handle)["devices"], "3")


if __name__ == "__main__":
    unittest.main()
