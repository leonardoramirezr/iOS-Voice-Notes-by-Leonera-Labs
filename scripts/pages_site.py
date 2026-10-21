#!/usr/bin/env python3
"""Renders the GitHub Pages site that serves the over-the-air (OTA) installs.

Subcommands:
  urls  Print the page, manifest and install URLs of a build as key=value lines.
  add   Add a build folder to a site directory, prune old builds and render every page.

Site layout: one folder per tag with VoiceNotes.ipa, manifest.plist, index.html, build.json and the
57/512 px icons; a root index.html listing every build with a button for the latest stable one; .nojekyll.
"""

from __future__ import annotations

import argparse
import datetime
import html
import json
import os
import plistlib
import shutil
import sys
import urllib.parse
from typing import Any, Dict, List, Optional

IPA_NAME = "VoiceNotes.ipa"
ICON_SMALL = "icon-57.png"
ICON_LARGE = "icon-512.png"
BUILD_FILE = "build.json"
DEFAULT_KEEP_BRANCH_BUILDS = 20


def normalize_base_url(url: str) -> str:
    url = url.strip()
    return url if url.endswith("/") else url + "/"


def build_urls(base_url: str, tag: str) -> Dict[str, str]:
    page_url = normalize_base_url(base_url) + urllib.parse.quote(tag) + "/"
    manifest_url = page_url + "manifest.plist"
    return {
        "page_url": page_url,
        "manifest_url": manifest_url,
        "ipa_url": page_url + IPA_NAME,
        "install_url": "itms-services://?action=download-manifest&url=" + urllib.parse.quote(manifest_url, safe=""),
    }


def manifest_plist(meta: Dict[str, Any], urls: Dict[str, str]) -> bytes:
    page_url = urls["page_url"]
    return plistlib.dumps(
        {
            "items": [
                {
                    "assets": [
                        {"kind": "software-package", "url": urls["ipa_url"]},
                        {"kind": "display-image", "url": page_url + ICON_SMALL},
                        {"kind": "full-size-image", "url": page_url + ICON_LARGE},
                    ],
                    "metadata": {
                        "bundle-identifier": meta["bundle_id"],
                        "bundle-version": meta["version"],
                        "kind": "software",
                        "title": meta["title"],
                    },
                }
            ]
        }
    )


STYLE = """
:root { color-scheme: light dark; --bg: #f2f2f7; --card: #ffffff; --text: #1c1c1e; --muted: #6c6c70;
  --accent: #0a66d8; --accent-text: #ffffff; --line: rgba(60, 60, 67, 0.18); --stable: #1f8a3b; --branch: #8e5b00; }
@media (prefers-color-scheme: dark) { :root { --bg: #000000; --card: #1c1c1e; --text: #f2f2f7; --muted: #a1a1a6;
  --accent: #3b8cff; --line: rgba(235, 235, 245, 0.18); --stable: #4cd964; --branch: #ffb340; } }
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text);
  font: 16px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif; }
main { max-width: 720px; margin: 0 auto; padding: 24px 16px 48px; }
header { display: flex; align-items: center; gap: 16px; margin-bottom: 20px; }
header img { width: 72px; height: 72px; border-radius: 16px; box-shadow: 0 4px 16px rgba(0, 0, 0, 0.18); }
h1 { font-size: 24px; margin: 0; }
h2 { font-size: 18px; margin: 28px 0 12px; }
.muted { color: var(--muted); }
.card { background: var(--card); border-radius: 18px; padding: 18px; margin-bottom: 14px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.06); }
.button { display: inline-block; background: var(--accent); color: var(--accent-text); text-decoration: none;
  font-weight: 600; padding: 12px 22px; border-radius: 999px; }
.button.secondary { background: transparent; color: var(--accent); border: 1px solid var(--line); }
.badge { display: inline-block; font-size: 12px; font-weight: 600; padding: 2px 8px; border-radius: 999px;
  border: 1px solid currentColor; }
.badge.stable { color: var(--stable); }
.badge.branch { color: var(--branch); }
dl { display: grid; grid-template-columns: max-content 1fr; gap: 6px 16px; margin: 16px 0 0; }
dt { color: var(--muted); }
dd { margin: 0; overflow-wrap: anywhere; }
.row { display: flex; align-items: center; justify-content: space-between; gap: 12px; flex-wrap: wrap; }
.row .title { font-weight: 600; }
.actions { display: flex; gap: 8px; }
a { color: var(--accent); }
code { font-size: 13px; }
"""


def _escape(value: Any) -> str:
    return html.escape(str(value), quote=True)


def _channel_badge(meta: Dict[str, Any]) -> str:
    if meta.get("channel") == "stable":
        return '<span class="badge stable">Stable</span>'
    return '<span class="badge branch">Pre-release</span>'


def _display_date(value: str) -> str:
    try:
        parsed = datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except (TypeError, ValueError):
        return str(value or "")
    return parsed.strftime("%Y-%m-%d %H:%M UTC")


def _page(title: str, body: str) -> str:
    return (
        "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        f"<title>{_escape(title)}</title>\n<style>{STYLE}</style>\n</head>\n<body>\n<main>\n{body}\n</main>\n</body>\n</html>\n"
    )


def build_page_html(meta: Dict[str, Any], urls: Dict[str, str]) -> str:
    repo = meta.get("repo", "")
    sha = meta.get("sha", "")
    commit = f'<a href="https://github.com/{_escape(repo)}/commit/{_escape(sha)}">{_escape(sha[:7])}</a>' if repo and sha else _escape(sha[:7])
    body = f"""<header>
<img src="{ICON_LARGE}" alt="">
<div><h1>{_escape(meta['title'])}</h1><div class="muted">{_escape(meta['tag'])} {_channel_badge(meta)}</div></div>
</header>
<div class="card">
<a class="button" href="{_escape(urls['install_url'])}">Install on iPhone</a>
<p class="muted">Open this page in Safari on an iPhone whose UDID is registered in the Apple Developer
portal, tap <strong>Install</strong> and confirm. The app appears on the home screen when the download finishes.</p>
<dl>
<dt>Version</dt><dd>{_escape(meta['version'])} ({_escape(meta.get('build_number', ''))})</dd>
<dt>Branch</dt><dd>{_escape(meta.get('branch', ''))}</dd>
<dt>Commit</dt><dd>{commit}</dd>
<dt>Built</dt><dd>{_escape(_display_date(meta.get('created_at', '')))}</dd>
<dt>Devices</dt><dd>{_escape(meta.get('devices', ''))}</dd>
<dt>IPA</dt><dd><a href="{IPA_NAME}">{IPA_NAME}</a></dd>
</dl>
</div>
<p><a href="../">All builds</a></p>"""
    return _page(f"{meta['title']} {meta['tag']}", body)


def sort_key(meta: Dict[str, Any]) -> tuple:
    try:
        run_number = int(meta.get("run_number", 0))
    except (TypeError, ValueError):
        run_number = 0
    return (str(meta.get("created_at", "")), run_number)


def index_html(builds: List[Dict[str, Any]], base_url: str, title: str) -> str:
    ordered = sorted(builds, key=sort_key, reverse=True)
    stable = [meta for meta in ordered if meta.get("channel") == "stable"]
    parts = [
        f'<header><img src="{_escape(urlsafe_relative(ordered[0]["tag"]) + ICON_LARGE) if ordered else ""}" alt="">'
        f"<div><h1>{_escape(title)}</h1><div class=\"muted\">Ad Hoc builds for registered iPhones</div></div></header>"
    ]
    if stable:
        latest = stable[0]
        urls = build_urls(base_url, latest["tag"])
        parts.append(
            '<div class="card"><div class="muted">Latest stable version</div>'
            f'<h2 style="margin-top:4px">{_escape(latest["tag"])}</h2>'
            f'<div class="actions"><a class="button" href="{_escape(urls["install_url"])}">Install latest stable</a>'
            f'<a class="button secondary" href="{_escape(urlsafe_relative(latest["tag"]))}">Details</a></div></div>'
        )
    else:
        parts.append('<div class="card muted">No stable version has been published from main yet.</div>')
    parts.append("<h2>All builds</h2>")
    for meta in ordered:
        urls = build_urls(base_url, meta["tag"])
        parts.append(
            '<div class="card"><div class="row"><div>'
            f'<div class="title">{_escape(meta["tag"])} {_channel_badge(meta)}</div>'
            f'<div class="muted">{_escape(meta.get("branch", ""))} · {_escape(meta.get("sha", "")[:7])} · '
            f'{_escape(_display_date(meta.get("created_at", "")))}</div></div>'
            f'<div class="actions"><a class="button" href="{_escape(urls["install_url"])}">Install</a>'
            f'<a class="button secondary" href="{_escape(urlsafe_relative(meta["tag"]))}">Details</a></div>'
            "</div></div>"
        )
    return _page(f"{title} builds", "\n".join(parts))


def urlsafe_relative(tag: str) -> str:
    return urllib.parse.quote(tag) + "/"


def load_builds(site: str) -> List[Dict[str, Any]]:
    builds = []
    for name in sorted(os.listdir(site)):
        path = os.path.join(site, name, BUILD_FILE)
        if os.path.isdir(os.path.join(site, name)) and os.path.isfile(path):
            with open(path, encoding="utf-8") as handle:
                meta = json.load(handle)
            meta["tag"] = name
            builds.append(meta)
    return builds


def remove_foreign_entries(site: str) -> None:
    """Keeps only top-level folders that contain build.json (the branch may have been created from code)."""
    for name in os.listdir(site):
        path = os.path.join(site, name)
        if os.path.isdir(path) and not os.path.islink(path) and os.path.isfile(os.path.join(path, BUILD_FILE)):
            continue
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.remove(path)


def prune(site: str, builds: List[Dict[str, Any]], keep_branch_builds: int) -> List[Dict[str, Any]]:
    stable = [meta for meta in builds if meta.get("channel") == "stable"]
    branch = sorted((meta for meta in builds if meta.get("channel") != "stable"), key=sort_key, reverse=True)
    kept_branch = branch[:keep_branch_builds]
    for meta in branch[keep_branch_builds:]:
        shutil.rmtree(os.path.join(site, meta["tag"]))
    return stable + kept_branch


def render_build_folder(site: str, meta: Dict[str, Any], base_url: str) -> None:
    folder = os.path.join(site, meta["tag"])
    urls = build_urls(base_url, meta["tag"])
    with open(os.path.join(folder, "manifest.plist"), "wb") as handle:
        handle.write(manifest_plist(meta, urls))
    with open(os.path.join(folder, "index.html"), "w", encoding="utf-8") as handle:
        handle.write(build_page_html(meta, urls))


def add_build(args: argparse.Namespace) -> Dict[str, str]:
    site = args.site
    os.makedirs(site, exist_ok=True)
    remove_foreign_entries(site)
    folder = os.path.join(site, args.tag)
    if os.path.exists(folder):
        shutil.rmtree(folder)
    os.makedirs(folder)
    shutil.copyfile(args.ipa, os.path.join(folder, IPA_NAME))
    shutil.copyfile(args.icon57, os.path.join(folder, ICON_SMALL))
    shutil.copyfile(args.icon512, os.path.join(folder, ICON_LARGE))
    created_at = args.created_at or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    meta = {
        "tag": args.tag,
        "channel": args.channel,
        "title": args.title,
        "bundle_id": args.bundle_id,
        "version": args.version,
        "build_number": args.build_number,
        "branch": args.branch,
        "sha": args.sha,
        "repo": args.repo,
        "run_id": args.run_id,
        "run_number": args.run_number,
        "devices": args.devices,
        "created_at": created_at,
        "ipa": IPA_NAME,
    }
    with open(os.path.join(folder, BUILD_FILE), "w", encoding="utf-8") as handle:
        json.dump(meta, handle, indent=2, sort_keys=True)
        handle.write("\n")

    builds = prune(site, load_builds(site), args.keep_branch_builds)
    for build in builds:
        render_build_folder(site, build, args.base_url)
    with open(os.path.join(site, "index.html"), "w", encoding="utf-8") as handle:
        handle.write(index_html(builds, args.base_url, args.title))
    with open(os.path.join(site, ".nojekyll"), "w", encoding="utf-8") as handle:
        handle.write("")
    return build_urls(args.base_url, args.tag)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    urls = sub.add_parser("urls")
    urls.add_argument("--base-url", required=True)
    urls.add_argument("--tag", required=True)

    add = sub.add_parser("add")
    add.add_argument("--site", required=True)
    add.add_argument("--base-url", required=True)
    add.add_argument("--tag", required=True)
    add.add_argument("--channel", choices=("stable", "branch"), required=True)
    add.add_argument("--ipa", required=True)
    add.add_argument("--icon57", required=True)
    add.add_argument("--icon512", required=True)
    add.add_argument("--title", required=True)
    add.add_argument("--bundle-id", required=True)
    add.add_argument("--version", required=True)
    add.add_argument("--build-number", default="")
    add.add_argument("--branch", default="")
    add.add_argument("--sha", default="")
    add.add_argument("--repo", default="")
    add.add_argument("--run-id", default="")
    add.add_argument("--run-number", default="0")
    add.add_argument("--devices", default="")
    add.add_argument("--created-at", default="")
    add.add_argument("--keep-branch-builds", type=int, default=DEFAULT_KEEP_BRANCH_BUILDS)

    args = parser.parse_args(argv)
    if args.command == "urls":
        for key, value in build_urls(args.base_url, args.tag).items():
            print(f"{key}={value}")
        return 0
    if args.command == "add":
        for key, value in add_build(args).items():
            print(f"{key}={value}")
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
