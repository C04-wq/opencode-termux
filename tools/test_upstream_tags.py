#!/usr/bin/env python3
"""Regression tests for stable OpenCode tag selection across all git refs."""
import unittest

from upstream_tags import resolve


def lightweight(tag: str, sha: str) -> str:
    return f"{sha}\trefs/tags/{tag}"


def annotated(tag: str, tag_sha: str, commit_sha: str) -> str:
    return "\n".join((
        lightweight(tag, tag_sha),
        f"{commit_sha}\trefs/tags/{tag}^{{}}",
    ))


class UpstreamTagsTest(unittest.TestCase):
    def test_selects_highest_numeric_stable_tag_across_major_versions(self) -> None:
        refs = [
            lightweight("v2.99.99", "a" * 40),
            lightweight("v3.0.0", "b" * 40),
            lightweight("v1.99.0", "d" * 40),
            annotated("v3.1.0", "e" * 40, "f" * 40),
            lightweight("v3.0.0-rc.1", "c" * 40),
            lightweight("v2.100.0", "invalid"),
        ]
        self.assertEqual(resolve("\n".join(refs)), ("v3.1.0", "3.1.0", "f" * 40))

    def test_uses_peeled_commit_for_annotated_tags(self) -> None:
        tag_sha = "a" * 40
        commit_sha = "b" * 40
        self.assertEqual(
            resolve(annotated("v2.3.2", tag_sha, commit_sha)),
            ("v2.3.2", "2.3.2", commit_sha),
        )

    def test_compares_minor_and_patch_numerically(self) -> None:
        refs = [
            lightweight("v2.9.99", "a" * 40),
            lightweight("v2.10.0", "b" * 40),
            lightweight("v2.10.1", "c" * 40),
            lightweight("v2.10.1-beta.1", "d" * 40),
        ]
        self.assertEqual(resolve("\n".join(refs)), ("v2.10.1", "2.10.1", "c" * 40))

    def test_rejects_empty_or_unusable_tag_lists(self) -> None:
        with self.assertRaisesRegex(ValueError, "No stable official"):
            resolve("")

    def test_ignores_malformed_lines_and_invalid_shas(self) -> None:
        payload = "not-a-sha refs/tags/v9.9.9\n" + lightweight("v2.3.2", "a" * 40)
        self.assertEqual(resolve(payload), ("v2.3.2", "2.3.2", "a" * 40))


if __name__ == "__main__":
    unittest.main()
