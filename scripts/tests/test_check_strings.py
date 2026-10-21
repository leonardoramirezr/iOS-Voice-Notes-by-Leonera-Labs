import json
import os
import tempfile
import unittest

import helpers
import check_strings


def catalog(entries):
    strings = {}
    for key, values in entries.items():
        strings[key] = {"localizations": {
            language: {"stringUnit": {"state": "translated", "value": value}} for language, value in values.items()
        }}
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


class CheckStringsTests(unittest.TestCase):
    def test_used_keys_are_found(self):
        with tempfile.TemporaryDirectory() as directory:
            with open(os.path.join(directory, "A.swift"), "w") as handle:
                handle.write('let a = String(localized: "a.key", defaultValue: "A")\n'
                             'let b = String(\n    localized: "b.key", defaultValue: "B \\(x)")\n')
            self.assertEqual(sorted(check_strings.used_keys(directory)), ["a.key", "b.key"])

    def test_catalog_errors(self):
        keys = {"ok": ["A.swift"], "missing": ["A.swift"], "no.es": ["A.swift"], "placeholder": ["A.swift"]}
        data = catalog({
            "ok": {"en": "Saved to %@", "es": "Guardado en %@"},
            "no.es": {"en": "Hello"},
            "placeholder": {"en": "%lld notes", "es": "notas"},
            "unused": {"en": "x", "es": "y"},
        })
        errors = check_strings.check_catalog(data, keys)
        joined = "\n".join(errors)
        self.assertIn("missing catalog entry for 'missing'", joined)
        self.assertIn("'no.es' has no es translation", joined)
        self.assertIn("'placeholder' placeholders differ", joined)
        self.assertIn("'unused' is not used", joined)
        self.assertNotIn("'ok'", joined)

    def test_repository_strings_are_complete(self):
        self.assertEqual(check_strings.main([]), 0)



def setUpModule():
    helpers.silence_stdout()


def tearDownModule():
    helpers.restore_stdout()


if __name__ == "__main__":
    unittest.main()
