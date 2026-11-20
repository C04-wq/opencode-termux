#!/usr/bin/env python3
"""Regression tests for official OpenCode 2.x tag selection."""
import json
import unittest

from upstream_tags import resolve


def ref(tag: str, sha: str, kind: str = "commit") -> dict:
    return {"ref": f"refs/tags/{tag}", "object": {"sha": sha, "type": kind}}


class UpstreamTagsTest(unittest.TestCase):
    def test_selects_highest_numeric_stable_v2_tag(self) -> None:
        refs = [
            ref("v2.9.99", "a" * 40),
            ref("v2.10.0", "b" * 40),
            ref("v2.10.0-rc.1", "c" * 40),
            ref("v1.99.0", "d" * 40),
            ref("v2.11.0", "e" * 40, "tag"),
            ref("v2.8.0", "invalid"),
        ]
        self.assertEqual(resolve(json.dumps(refs)), ("v2.10.0", "2.10.0", "b" * 40))

    def test_rejects_empty_or_unusable_tag_lists(self) -> None:
        with self.assertRaisesRegex(ValueError, "No stable official"):
            resolve("[]")

    def test_rejects_non_array_payload(self) -> None:
        with self.assertRaisesRegex(ValueError, "JSON array"):
            resolve('{"ref":"refs/tags/v2.3.2"}')


if __name__ == "__main__":
    unittest.main()
