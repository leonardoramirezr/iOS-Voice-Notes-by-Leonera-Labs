"""Shared helpers for the script tests."""

import os
import sys

SCRIPTS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, SCRIPTS_DIR)

_saved_stdout = []


def silence_stdout():
    """Captures stdout so GitHub Actions does not turn expected `::error::` lines into annotations."""
    import io

    _saved_stdout.append(sys.stdout)
    sys.stdout = io.StringIO()


def restore_stdout():
    sys.stdout = _saved_stdout.pop()
