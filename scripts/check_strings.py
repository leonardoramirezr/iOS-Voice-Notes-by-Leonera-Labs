#!/usr/bin/env python3
"""Checks that every localized UI string has English and Spanish translations.

- Every `String(localized: "key", ...)` used under App/ must exist in App/Resources/Localizable.xcstrings
  with non-empty "en" and "es" values whose format placeholders match.
- Catalog keys that are no longer used are reported as errors so the catalog stays clean.
- App/Resources/en.lproj/InfoPlist.strings and es.lproj/InfoPlist.strings must define the same keys.
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import re
import sys
from typing import Dict, List, Optional

KEY_PATTERN = re.compile(r'String\(\s*localized:\s*"([^"\\]+)"')
PLACEHOLDER_PATTERN = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f|\.\d+f)")
STRINGS_LINE = re.compile(r'^\s*"([^"]+)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')
LANGUAGES = ("en", "es")


def used_keys(app_dir: str) -> Dict[str, List[str]]:
    keys: Dict[str, List[str]] = collections.defaultdict(list)
    for directory, _, files in os.walk(app_dir):
        for name in files:
            if name.endswith(".swift"):
                path = os.path.join(directory, name)
                with open(path, encoding="utf-8") as handle:
                    for key in KEY_PATTERN.findall(handle.read()):
                        keys[key].append(os.path.relpath(path, app_dir))
    return keys


def placeholders(value: str) -> List[str]:
    return sorted(PLACEHOLDER_PATTERN.findall(value))


def check_catalog(catalog: dict, keys: Dict[str, List[str]]) -> List[str]:
    errors = []
    strings = catalog.get("strings", {})
    if catalog.get("sourceLanguage") != "en":
        errors.append("Localizable.xcstrings must use English as sourceLanguage")
    for key in sorted(keys):
        entry = strings.get(key)
        if entry is None:
            errors.append(f"missing catalog entry for '{key}' (used in {', '.join(sorted(set(keys[key])))})")
            continue
        values = {}
        for language in LANGUAGES:
            unit = ((entry.get("localizations") or {}).get(language) or {}).get("stringUnit") or {}
            value = unit.get("value", "")
            if not value.strip():
                errors.append(f"'{key}' has no {language} translation")
            values[language] = value
        if all(values.values()) and placeholders(values["en"]) != placeholders(values["es"]):
            errors.append(f"'{key}' placeholders differ: en {placeholders(values['en'])} vs es {placeholders(values['es'])}")
    for key in sorted(set(strings) - set(keys)):
        errors.append(f"catalog entry '{key}' is not used by the app")
    return errors


def read_strings_file(path: str) -> Dict[str, str]:
    values = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            stripped = line.strip()
            if not stripped or stripped.startswith("/*") or stripped.startswith("//") or stripped.startswith("*"):
                continue
            match = STRINGS_LINE.match(line)
            if not match:
                raise ValueError(f"{path}: cannot parse line: {line.rstrip()}")
            values[match.group(1)] = match.group(2)
    return values


def check_info_plist_strings(resources: str) -> List[str]:
    errors = []
    tables = {}
    for language in LANGUAGES:
        path = os.path.join(resources, f"{language}.lproj", "InfoPlist.strings")
        if not os.path.exists(path):
            errors.append(f"missing {os.path.relpath(path, resources)}")
            continue
        try:
            tables[language] = read_strings_file(path)
        except ValueError as error:
            errors.append(str(error))
    if len(tables) == len(LANGUAGES) and set(tables["en"]) != set(tables["es"]):
        errors.append(f"InfoPlist.strings keys differ: en {sorted(tables['en'])} vs es {sorted(tables['es'])}")
    return errors


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser.add_argument("--app-dir", default=os.path.join(root, "App"))
    args = parser.parse_args(argv)

    resources = os.path.join(args.app_dir, "Resources")
    with open(os.path.join(resources, "Localizable.xcstrings"), encoding="utf-8") as handle:
        catalog = json.load(handle)
    keys = used_keys(args.app_dir)
    errors = check_catalog(catalog, keys) + check_info_plist_strings(resources)
    for error in errors:
        print(f"::error title=Localization::{error}")
    if errors:
        return 1
    print(f"Localization OK: {len(keys)} keys translated to {', '.join(LANGUAGES)}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
