#!/usr/bin/env python3
"""Verifies that every bundle in an exported IPA carries an Ad Hoc provisioning profile.

Usage: verify_ipa.py <ipa> --team TEAM_ID --bundle-id BUNDLE_ID [--skip-codesign]

For each .app and .appex bundle the script decodes embedded.mobileprovision and checks that the
profile lists provisioned devices (Ad Hoc), does not provision all devices (Enterprise), has
get-task-allow disabled (not a development profile) and matches the team and bundle identifier.
It prints the device count and writes `devices=<n>` to $GITHUB_OUTPUT.
"""

from __future__ import annotations

import argparse
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from typing import Any, Dict, List, Optional


class VerificationError(Exception):
    pass


def decode_profile(path: str) -> Dict[str, Any]:
    """Decodes a CMS-signed provisioning profile, using `security cms` when available."""
    if shutil.which("security"):
        result = subprocess.run(["security", "cms", "-D", "-i", path], capture_output=True)
        if result.returncode == 0 and result.stdout:
            return plistlib.loads(result.stdout)
    with open(path, "rb") as handle:
        data = handle.read()
    start = data.find(b"<?xml")
    end = data.find(b"</plist>")
    if start < 0 or end < 0:
        raise VerificationError(f"{path} does not contain a property list")
    return plistlib.loads(data[start:end + len(b"</plist>")])


def find_bundles(root: str) -> List[str]:
    bundles = []
    for directory, subdirectories, _ in os.walk(root):
        for name in subdirectories:
            if name.endswith(".app") or name.endswith(".appex"):
                bundles.append(os.path.join(directory, name))
    return sorted(bundles)


def check_bundle(bundle: str, team_id: str) -> Dict[str, Any]:
    name = os.path.basename(bundle)
    with open(os.path.join(bundle, "Info.plist"), "rb") as handle:
        info = plistlib.load(handle)
    identifier = info.get("CFBundleIdentifier", "")
    profile_path = os.path.join(bundle, "embedded.mobileprovision")
    if not os.path.exists(profile_path):
        raise VerificationError(f"{name} has no embedded.mobileprovision")
    profile = decode_profile(profile_path)
    entitlements = profile.get("Entitlements") or {}
    devices = profile.get("ProvisionedDevices") or []
    if profile.get("ProvisionsAllDevices"):
        raise VerificationError(f"{name}: the profile provisions all devices (Enterprise), not Ad Hoc")
    if not devices:
        raise VerificationError(f"{name}: the profile has no ProvisionedDevices, so it is not an Ad Hoc profile")
    if entitlements.get("get-task-allow"):
        raise VerificationError(f"{name}: get-task-allow is true, so it is a development profile")
    teams = profile.get("TeamIdentifier") or []
    if team_id and team_id not in teams:
        raise VerificationError(f"{name}: profile team {teams} does not include {team_id}")
    application_identifier = entitlements.get("application-identifier", "")
    if not application_identifier.endswith("." + identifier):
        raise VerificationError(
            f"{name}: profile application-identifier {application_identifier!r} does not match {identifier!r}"
        )
    return {
        "bundle": name,
        "identifier": identifier,
        "profile": profile.get("Name", ""),
        "expires": str(profile.get("ExpirationDate", "")),
        "devices": len(devices),
    }


def verify_payload(root: str, team_id: str, bundle_id: str) -> List[Dict[str, Any]]:
    bundles = find_bundles(os.path.join(root, "Payload"))
    if not bundles:
        raise VerificationError("the IPA has no Payload/*.app bundle")
    results = [check_bundle(bundle, team_id) for bundle in bundles]
    main_identifiers = [result["identifier"] for result in results if result["bundle"].endswith(".app")]
    if bundle_id and bundle_id not in main_identifiers:
        raise VerificationError(f"no .app bundle has the identifier {bundle_id}; found {main_identifiers}")
    for result in results:
        if result["bundle"].endswith(".appex") and not result["identifier"].startswith(bundle_id + "."):
            raise VerificationError(f"extension {result['identifier']} must use the prefix {bundle_id}.")
    return results


def codesign_verify(root: str) -> None:
    for bundle in find_bundles(os.path.join(root, "Payload")):
        if bundle.endswith(".app") and os.path.dirname(bundle).endswith("Payload"):
            result = subprocess.run(
                ["codesign", "--verify", "--deep", "--strict", "--verbose=2", bundle], capture_output=True, text=True
            )
            if result.returncode != 0:
                raise VerificationError(f"codesign verification failed for {bundle}: {result.stderr.strip()}")


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("ipa")
    parser.add_argument("--team", default="")
    parser.add_argument("--bundle-id", default="")
    parser.add_argument("--skip-codesign", action="store_true")
    args = parser.parse_args(argv)

    with tempfile.TemporaryDirectory() as root:
        with zipfile.ZipFile(args.ipa) as archive:
            archive.extractall(root)
        try:
            results = verify_payload(root, args.team, args.bundle_id)
            if not args.skip_codesign:
                codesign_verify(root)
        except VerificationError as error:
            print(f"::error title=IPA verification::{error}")
            return 1

    for result in results:
        print(
            f"{result['bundle']}: {result['identifier']} — profile '{result['profile']}', "
            f"{result['devices']} devices, expires {result['expires']}"
        )
    devices = min(result["devices"] for result in results)
    print(f"Ad Hoc provisioning verified for {len(results)} bundle(s); devices included: {devices}.")
    output_path = os.environ.get("GITHUB_OUTPUT")
    if output_path:
        with open(output_path, "a", encoding="utf-8") as handle:
            handle.write(f"devices={devices}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
