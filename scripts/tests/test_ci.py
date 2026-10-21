import os
import plistlib
import tempfile
import unittest

import helpers  # noqa: F401  (adds scripts/ to sys.path)
import ci

ALL_SECRETS = {"ASC_KEY_ID": "K", "ASC_ISSUER_ID": "I", "ASC_KEY_P8": "P", "APPLE_TEAM_ID": "T"}


class ModeTests(unittest.TestCase):
    def test_all_secrets_build_signed(self):
        self.assertEqual(ci.resolve_mode(ALL_SECRETS), ("signed", []))

    def test_no_secrets_build_unsigned(self):
        mode, missing = ci.resolve_mode({})
        self.assertEqual(mode, "unsigned")
        self.assertEqual(missing, list(ci.SECRET_NAMES))

    def test_partial_secrets_fail_and_name_the_missing_ones(self):
        env = dict(ALL_SECRETS, ASC_KEY_P8="  ", APPLE_TEAM_ID="")
        self.assertEqual(ci.resolve_mode(env), ("error", ["ASC_KEY_P8", "APPLE_TEAM_ID"]))

    def test_force_unsigned_wins(self):
        self.assertEqual(ci.resolve_mode(dict(ALL_SECRETS, FORCE_UNSIGNED="true")), ("unsigned", []))

    def test_cli_partial_secrets_exit_code(self):
        saved = dict(os.environ)
        try:
            os.environ.clear()
            os.environ.update({"ASC_KEY_ID": "K"})
            self.assertEqual(ci.main(["mode"]), 1)
        finally:
            os.environ.clear()
            os.environ.update(saved)


LS_REMOTE = """\
1111111111111111111111111111111111111111\trefs/tags/0.9.0
2222222222222222222222222222222222222222\trefs/tags/0.10.0
3333333333333333333333333333333333333333\trefs/tags/build-7-abcdef1
4444444444444444444444444444444444444444\trefs/tags/0.2.1
5555555555555555555555555555555555555555\trefs/tags/v1.0.0
6666666666666666666666666666666666666666\trefs/tags/0.3.0
7777777777777777777777777777777777777777\trefs/tags/0.3.0^{}
"""


class VersionTests(unittest.TestCase):
    def setUp(self):
        self.tags = ci.parse_ls_remote(LS_REMOTE)

    def test_peeled_tags_use_the_commit(self):
        self.assertEqual(self.tags["0.3.0"], "7" * 40)

    def test_first_main_build_is_0_1_0(self):
        result = ci.compute_version("refs/heads/main", "a" * 40, "1", {})
        self.assertEqual(result["tag"], "0.1.0")
        self.assertEqual(result["channel"], "stable")
        self.assertEqual(result["prerelease"], "false")
        self.assertEqual(result["marketing_version"], "0.1.0")

    def test_main_increments_the_middle_number_numerically(self):
        result = ci.compute_version("refs/heads/main", "a" * 40, "42", self.tags)
        self.assertEqual(result["tag"], "0.11.0")
        self.assertEqual(result["build_number"], "42")
        self.assertEqual(result["reused_tag"], "false")

    def test_main_rerun_reuses_the_tag_on_head(self):
        result = ci.compute_version("refs/heads/main", "2" * 40, "43", self.tags)
        self.assertEqual(result["tag"], "0.10.0")
        self.assertEqual(result["reused_tag"], "true")

    def test_branch_build_name(self):
        result = ci.compute_version("refs/heads/feature/x", "1bca82e" + "0" * 33, "30", self.tags)
        self.assertEqual(result["tag"], "build-30-1bca82e")
        self.assertEqual(result["build_name"], "build-30-1bca82e")
        self.assertEqual(result["channel"], "branch")
        self.assertEqual(result["prerelease"], "true")
        self.assertEqual(result["marketing_version"], "0.10.0")
        self.assertEqual(result["branch"], "feature/x")

    def test_branch_without_stable_tags(self):
        result = ci.compute_version("refs/heads/dev", "abcdef1234", "5", {})
        self.assertEqual(result["marketing_version"], "0.0.0")

    def test_cli_reads_tags_file(self):
        with tempfile.TemporaryDirectory() as directory:
            tags_path = os.path.join(directory, "tags.txt")
            output_path = os.path.join(directory, "out.txt")
            with open(tags_path, "w") as handle:
                handle.write(LS_REMOTE)
            saved = os.environ.get("GITHUB_OUTPUT")
            os.environ["GITHUB_OUTPUT"] = output_path
            try:
                code = ci.main(["version", "--ref", "refs/heads/main", "--sha", "a" * 40, "--run-number", "9",
                                "--tags-file", tags_path])
            finally:
                if saved is None:
                    del os.environ["GITHUB_OUTPUT"]
                else:
                    os.environ["GITHUB_OUTPUT"] = saved
            self.assertEqual(code, 0)
            with open(output_path) as handle:
                self.assertIn("tag=0.11.0\n", handle.read())


class ExportOptionsTests(unittest.TestCase):
    def test_export_options(self):
        options = plistlib.loads(ci.export_options("TEAM123"))
        self.assertEqual(options["method"], "release-testing")
        self.assertEqual(options["signingStyle"], "automatic")
        self.assertEqual(options["teamID"], "TEAM123")


class ReleaseNotesTests(unittest.TestCase):
    def test_notes_link_the_https_page_and_show_the_install_url_as_code(self):
        notes = ci.release_notes(
            tag="build-3-abc1234", channel="branch", page_url="https://x.github.io/r/build-3-abc1234/",
            install_url="itms-services://?action=download-manifest&url=https%3A%2F%2Fx", branch="dev",
            sha="abc1234def", repo="o/r", run_url="https://github.com/o/r/actions/runs/1", devices="2",
        )
        self.assertIn("https://x.github.io/r/build-3-abc1234/", notes)
        self.assertIn("```\nitms-services://", notes)
        self.assertIn("Pre-release", notes)
        self.assertIn("devices: 2", notes)


if __name__ == "__main__":
    unittest.main()
