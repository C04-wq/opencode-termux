#!/usr/bin/env python3
"""Regression tests for the Bun lockfile parser."""
import tempfile
import unittest
from pathlib import Path
from bun_lock import load_bun_lock


class BunLockTests(unittest.TestCase):
    def test_nested_trailing_commas(self):
        source = """{
          "workspaces": {
            "packages/core": {
              "dependencies": {
                "@ff-labs/fff-bun": "0.10.5",
              },
            },
          },
        }"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bun.lock"
            path.write_text(source, encoding="utf-8")
            lock = load_bun_lock(path)
        self.assertEqual(lock["workspaces"]["packages/core"]["dependencies"]["@ff-labs/fff-bun"], "0.10.5")

    def test_commas_inside_strings_are_preserved(self):
        source = '{"workspaces": {}, "value": "literal,} and ,]"}'
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bun.lock"
            path.write_text(source, encoding="utf-8")
            lock = load_bun_lock(path)
        self.assertEqual(lock["value"], "literal,} and ,]")

    def test_invalid_json_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bun.lock"
            path.write_text('{"workspaces": {, "broken": true}}', encoding="utf-8")
            with self.assertRaises(ValueError):
                load_bun_lock(path)


if __name__ == "__main__":
    unittest.main()
