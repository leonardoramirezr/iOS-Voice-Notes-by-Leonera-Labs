"""Integration test: publish-pages.sh against a local bare repository."""

import os
import shutil
import subprocess
import tempfile
import unittest

import helpers

SCRIPT = os.path.join(helpers.SCRIPTS_DIR, "publish-pages.sh")
ENV = dict(
    os.environ,
    GIT_AUTHOR_NAME="Test",
    GIT_AUTHOR_EMAIL="test@example.com",
    GIT_COMMITTER_NAME="Test",
    GIT_COMMITTER_EMAIL="test@example.com",
    PAGES_RETRY_DELAY="0",
    PAGES_MAX_ATTEMPTS="8",
)


def git(*args, cwd):
    return subprocess.run(["git", *args], cwd=cwd, env=ENV, check=True, capture_output=True, text=True).stdout.strip()


@unittest.skipUnless(shutil.which("git") and shutil.which("bash"), "git and bash are required")
class PublishPagesTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        root = self.directory.name
        self.remote = os.path.join(root, "remote.git")
        git("init", "--bare", "--quiet", self.remote, cwd=root)
        seed = os.path.join(root, "seed")
        os.makedirs(seed)
        git("init", "--quiet", "-b", "main", cwd=seed)
        with open(os.path.join(seed, "README.md"), "w") as handle:
            handle.write("code\n")
        with open(os.path.join(seed, ".gitignore"), "w") as handle:
            handle.write("*.ipa\n")
        git("add", "-A", cwd=seed)
        git("commit", "--quiet", "-m", "code", cwd=seed)
        git("remote", "add", "origin", self.remote, cwd=seed)
        git("push", "--quiet", "origin", "main", cwd=seed)
        # The Pages branch may have been created from the source code.
        git("push", "--quiet", "origin", "main:gh-pages", cwd=seed)
        self.files = {}
        for name in ("VoiceNotes.ipa", "icon-57.png", "icon-512.png"):
            path = os.path.join(root, name)
            with open(path, "wb") as handle:
                handle.write(os.urandom(64))
            self.files[name] = path
        self.clones = root

    def tearDown(self):
        self.directory.cleanup()

    def clone(self, name):
        path = os.path.join(self.clones, name)
        git("clone", "--quiet", "--depth", "1", "--branch", "main", "file://" + self.remote, path, cwd=self.clones)
        return path

    def publish(self, clone, tag, channel="branch", run_number="1", background=False):
        command = [
            "bash", SCRIPT, "--tag", tag, "--channel", channel, "--ipa", self.files["VoiceNotes.ipa"],
            "--icon57", self.files["icon-57.png"], "--icon512", self.files["icon-512.png"],
            "--base-url", "https://example.github.io/repo/", "--title", "Voice Notes", "--bundle-id", "com.example",
            "--version", "0.0.0", "--run-number", run_number, "--created-at", f"2026-10-21T10:{int(run_number):02d}:00Z",
        ]
        if background:
            return subprocess.Popen(command, cwd=clone, env=ENV, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        result = subprocess.run(command, cwd=clone, env=ENV, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def pages_tree(self):
        return sorted(git("ls-tree", "-r", "--name-only", "gh-pages", cwd=self.remote).splitlines())

    def test_publish_rewrites_branch_as_single_orphan_commit(self):
        clone = self.clone("one")
        self.publish(clone, "build-1-aaaaaaa", run_number="1")
        self.publish(clone, "0.1.0", channel="stable", run_number="2")
        self.assertEqual(git("rev-list", "--count", "gh-pages", cwd=self.remote), "1")
        self.assertEqual(git("log", "-1", "--format=%P", "gh-pages", cwd=self.remote), "")
        tree = self.pages_tree()
        self.assertIn("build-1-aaaaaaa/VoiceNotes.ipa", tree)
        self.assertIn("0.1.0/VoiceNotes.ipa", tree)
        self.assertIn("0.1.0/manifest.plist", tree)
        self.assertIn(".nojekyll", tree)
        self.assertIn("index.html", tree)
        self.assertNotIn("README.md", tree)
        self.assertNotIn(".gitignore", tree)

    def test_concurrent_publishes_do_not_lose_builds(self):
        clones = [self.clone(f"c{index}") for index in range(4)]
        processes = [
            self.publish(clone, f"build-{index + 1}-bbbbbbb", run_number=str(index + 1), background=True)
            for index, clone in enumerate(clones)
        ]
        for process in processes:
            output, _ = process.communicate(timeout=120)
            self.assertEqual(process.returncode, 0, output)
        tree = self.pages_tree()
        for index in range(4):
            self.assertIn(f"build-{index + 1}-bbbbbbb/VoiceNotes.ipa", tree)
        self.assertEqual(git("rev-list", "--count", "gh-pages", cwd=self.remote), "1")


if __name__ == "__main__":
    unittest.main()
