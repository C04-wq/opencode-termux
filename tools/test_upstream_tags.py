#!/usr/bin/env python3
"""Regression tests for stable OpenCode tag selection across major versions."""
import json
import unittest

from upstream_tags import resolve


def ref(tag: str, sha: str, kind: str = "commit") -> dict:
    return {"ref": f"refs/tags/{tag}", "object": {"sha": sha, "type": kind}}


class UpstreamTagsTest(unittest.TestCase):
    def test_selects_highest_numeric_stable_tag_across_major_versions(self) -> None:
        refs = [
            ref("v2.99.99", "a" * 40),
            ref("v3.0.0", "b" * 40),
            ref("v3.0.0-rc.1", "c" * 40),
            ref("v1.99.0", "d" * 40),
            ref("v3.1.0", "e" * 40, "tag"),
            ref("v2.100.0", "invalid"),
        ]
        self.assertEqual(resolve(json.dumps(refs)), ("v3.0.0", "3.0.0", "b" * 40))

    def test_compares_minor_and_patch_numerically(self) -> None:
        refs = [
            ref("v2.9.99", "a" * 40),
            ref("v2.10.0", "b" * 40),
            ref("v2.10.1", "c" * 40),
            ref("v2.10.1-beta.1", "d" * 40),
        ]
        self.assertEqual(resolve(json.dumps(refs)), ("v2.10.1", "2.10.1", "c" * 40))

    def test_rejects_empty_or_unusable_tag_lists(self) -> None:
        with self.assertRaisesRegex(ValueError, "No stable official"):
            resolve("[]")

    def test_rejects_non_array_payload(self) -> None:
        with self.assertRaisesRegex(ValueError, "JSON array"):
            resolve('{"ref":"refs/tags/v2.3.2"}')


if __name__ == "__main__":
    unittest.main()
