#!/usr/bin/env python3
"""CI helpers for the build workflow (Python standard library only).

Subcommands:
  mode            Decide between a signed and an unsigned build from the signing secrets.
  version         Compute the tag, channel and version numbers for this run.
  export-options  Write the ExportOptions.plist used for the Ad Hoc export.
  release-notes   Render the Markdown notes of the GitHub release.
"""

from __future__ import annotations

import argparse
import os
import plistlib
import re
import subprocess
import sys
from typing import Dict, List, Mapping, Optional, Tuple

SECRET_NAMES = ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8", "APPLE_TEAM_ID")
STABLE_TAG = re.compile(r"^0\.(\d+)\.0$")
MAIN_REF = "refs/heads/main"


def is_truthy(value: Optional[str]) -> bool:
    return (value or "").strip().lower() in ("1", "true", "yes", "on")


def write_outputs(values: Mapping[str, str]) -> None:
    """Appends key=value pairs to $GITHUB_OUTPUT, or prints them when running locally."""
    lines = [f"{key}={value}" for key, value in values.items()]
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as handle:
            handle.write("\n".join(lines) + "\n")
    for line in lines:
        print(line)


def resolve_mode(env: Mapping[str, str]) -> Tuple[str, List[str]]:
    """Returns ("signed" | "unsigned" | "error", missing secret names)."""
    if is_truthy(env.get("FORCE_UNSIGNED")):
        return "unsigned", []
    present = [name for name in SECRET_NAMES if (env.get(name) or "").strip()]
    missing = [name for name in SECRET_NAMES if name not in present]
    if not present:
        return "unsigned", missing
    if missing:
        return "error", missing
    return "signed", []


def parse_ls_remote(text: str) -> Dict[str, str]:
    """Maps tag names to commit SHAs from `git ls-remote --tags` output (peeled entries win)."""
    tags: Dict[str, str] = {}
    peeled: Dict[str, str] = {}
    for line in text.splitlines():
        parts = line.strip().split()
        if len(parts) != 2 or not parts[1].startswith("refs/tags/"):
            continue
        sha, ref = parts
        name = ref[len("refs/tags/"):]
        if name.endswith("^{}"):
            peeled[name[:-3]] = sha
        else:
            tags[name] = sha
    tags.update(peeled)
    return tags


def stable_tags(tags: Mapping[str, str]) -> List[Tuple[int, str]]:
    """Returns (minor, name) pairs of 0.x.0 tags sorted numerically."""
    found = []
    for name in tags:
        match = STABLE_TAG.match(name)
        if match:
            found.append((int(match.group(1)), name))
    return sorted(found)


def compute_version(ref: str, sha: str, run_number: str, tags: Mapping[str, str]) -> Dict[str, str]:
    stable = stable_tags(tags)
    last_stable = stable[-1][1] if stable else None
    reused = False
    if ref == MAIN_REF:
        existing = [name for _, name in stable if tags[name] == sha]
        if existing:
            tag = existing[-1]
            reused = True
        else:
            next_minor = stable[-1][0] + 1 if stable else 1
            tag = f"0.{next_minor}.0"
        channel = "stable"
        marketing_version = tag
    else:
        tag = f"build-{run_number}-{sha[:7]}"
        channel = "branch"
        marketing_version = last_stable or "0.0.0"
    branch = ref[len("refs/heads/"):] if ref.startswith("refs/heads/") else ref
    return {
        "tag": tag,
        "channel": channel,
        "prerelease": "false" if channel == "stable" else "true",
        "marketing_version": marketing_version,
        "build_number": str(run_number),
        "build_name": tag,
        "branch": branch,
        "short_sha": sha[:7],
        "reused_tag": "true" if reused else "false",
    }


def fetch_remote_tags(remote: str) -> Dict[str, str]:
    result = subprocess.run(
        ["git", "ls-remote", "--tags", remote], check=True, capture_output=True, text=True
    )
    return parse_ls_remote(result.stdout)


def export_options(team_id: str) -> bytes:
    return plistlib.dumps(
        {
            "method": "release-testing",
            "signingStyle": "automatic",
            "teamID": team_id,
            "destination": "export",
            "thinning": "<none>",
            "compileBitcode": False,
        }
    )


def release_notes(
    tag: str,
    channel: str,
    page_url: str,
    install_url: str,
    branch: str,
    sha: str,
    repo: str,
    run_url: str,
    devices: str,
) -> str:
    kind = "Stable release" if channel == "stable" else "Pre-release build"
    lines = [
        f"## {kind} `{tag}`",
        "",
        f"**Install on iPhone (open in Safari):** {page_url}",
        "",
        "Direct install URL (GitHub does not render `itms-services` links, copy it into Safari):",
        "",
        f"```\n{install_url}\n```",
        "",
        f"- Branch: `{branch}`",
        f"- Commit: https://github.com/{repo}/commit/{sha}",
        f"- Workflow run: {run_url}",
    ]
    if devices:
        lines.append(f"- Ad Hoc profile devices: {devices}")
    lines.append("")
    lines.append("Only iPhones whose UDID is registered in the Apple Developer portal can install this build.")
    return "\n".join(lines) + "\n"


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("mode")

    version = sub.add_parser("version")
    version.add_argument("--ref", default=os.environ.get("GITHUB_REF", ""))
    version.add_argument("--sha", default=os.environ.get("GITHUB_SHA", ""))
    version.add_argument("--run-number", default=os.environ.get("GITHUB_RUN_NUMBER", "0"))
    version.add_argument("--remote", default="origin")
    version.add_argument("--tags-file", help="Read `git ls-remote --tags` output from a file instead of the remote.")

    options = sub.add_parser("export-options")
    options.add_argument("--team", required=True)
    options.add_argument("--out", required=True)

    notes = sub.add_parser("release-notes")
    for name in ("tag", "channel", "page-url", "install-url", "branch", "sha", "repo", "run-url"):
        notes.add_argument(f"--{name}", required=True)
    notes.add_argument("--devices", default="")
    notes.add_argument("--out", required=True)

    args = parser.parse_args(argv)

    if args.command == "mode":
        mode, missing = resolve_mode(os.environ)
        if mode == "error":
            print(
                "::error title=Incomplete signing secrets::Missing secrets: "
                + ", ".join(missing)
                + ". Configure all of ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 and APPLE_TEAM_ID as repository "
                "secrets for a signed build, or none of them for an unsigned build."
            )
            return 1
        if mode == "unsigned":
            print("::notice title=Unsigned build::Signing secrets are not configured (or force_unsigned is set); "
                  "the workflow produces an unsigned IPA and skips the release and GitHub Pages.")
        write_outputs({"mode": mode})
        return 0

    if args.command == "version":
        if not args.sha:
            print("::error::Missing commit SHA.")
            return 1
        if args.tags_file:
            with open(args.tags_file, encoding="utf-8") as handle:
                tags = parse_ls_remote(handle.read())
        else:
            tags = fetch_remote_tags(args.remote)
        write_outputs(compute_version(args.ref, args.sha, args.run_number, tags))
        return 0

    if args.command == "export-options":
        with open(args.out, "wb") as handle:
            handle.write(export_options(args.team))
        print(f"Wrote {args.out}")
        return 0

    if args.command == "release-notes":
        text = release_notes(
            tag=args.tag,
            channel=args.channel,
            page_url=args.page_url,
            install_url=args.install_url,
            branch=args.branch,
            sha=args.sha,
            repo=args.repo,
            run_url=args.run_url,
            devices=args.devices,
        )
        with open(args.out, "w", encoding="utf-8") as handle:
            handle.write(text)
        print(text)
        return 0

    return 2


if __name__ == "__main__":
    sys.exit(main())
