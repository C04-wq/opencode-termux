#!/usr/bin/env python3
"""Regression tests for routing OpenCode's built-in updater to verified Termux releases."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
PATCH = (ROOT / "tools/patch-opencode-source.py").read_text(encoding="utf-8")
INSTALL = (ROOT / "install.sh").read_text(encoding="utf-8")


class TermuxUpdaterContract(unittest.TestCase):
    def test_internal_updater_reads_our_release_metadata_on_termux(self):
        self.assertIn('https://raw.githubusercontent.com/C04-wq/opencode-termux/main/release-checksums.json', PATCH)
        self.assertIn('nativeTermux', PATCH)
        self.assertLess(PATCH.index('if (nativeTermux) return "curl"'), PATCH.index('if (prefix && executable === path.join(prefix, "bin", "opencode"))'))
        self.assertIn('if (method === "apt" && !nativeTermux)', PATCH)
        self.assertIn('const nativeTermux = prefix !== undefined && launcher === path.join(prefix, "bin", "opencode")', PATCH)
        self.assertIn('data.sourceRepo !== "C04-wq/opencode-termux"', PATCH)
        self.assertIn('data.runtimeId !== "android-bionic-bun-v1"', PATCH)
        self.assertIn('data.archiveSha256X86_64', PATCH)
        self.assertIn('data.archiveNameX86_64 === expectedArchive', PATCH)

    def test_internal_update_pins_installer_to_checked_version(self):
        self.assertIn('OPENCODE_TERMUX_EXPECTED_VERSION="$1" OPENCODE_TERMUX_EXPECTED_RELEASE_TAG="$3" exec bash "$2"', PATCH)
        self.assertIn('"$VERSION" != "$OPENCODE_TERMUX_EXPECTED_VERSION"', INSTALL)
        self.assertIn('"$RELEASE_TAG" != "$OPENCODE_TERMUX_EXPECTED_RELEASE_TAG"', INSTALL)
        self.assertIn('.opencode-termux-release-tag', INSTALL)
        self.assertIn('return `${version}-termux.${revision}', PATCH)
        self.assertIn('current: () => Effect.gen(function* ()', PATCH)
        self.assertIn('return yield* Ref.get(installedVersion)', PATCH)
        self.assertIn('updater.current()', PATCH)
        self.assertIn('current.includes("-termux.") ? "curl"', PATCH)
        self.assertIn('if (version === current)', PATCH)
        self.assertIn('From ${current} → ${version}', PATCH)
        self.assertIn('.opencode-termux-release-tag', PATCH)

    def test_installer_still_verifies_release_archive_checksum(self):
        self.assertIn('ACTUAL="$(sha256sum "$STAGE/runtime.tar.gz"', INSTALL)
        self.assertIn('[[ "$ACTUAL" == "$HASH" ]]', INSTALL)
        self.assertIn('scripts/validate-runtime-archive.sh', INSTALL)

    def test_official_update_flow_is_enabled_and_not_replaced_by_launcher_checks(self):
        self.assertNotIn("OPENCODE_DISABLE_AUTOUPDATE", INSTALL)
        self.assertNotIn("OPENCODE_TERMUX_AUTOUPDATE", INSTALL)
        self.assertNotIn("AUTO_UPDATE_SKIP", INSTALL)
        self.assertNotIn("update-runtime.sh", INSTALL)
        self.assertNotIn("Verified OpenCode update", INSTALL)
        self.assertIn('nativeTermux', PATCH)
        self.assertIn('Updater.apply', PATCH)
        self.assertNotIn('https://opencode.ai/update/api/', PATCH)
        self.assertNotIn('https://github.com/anomalyco/opencode/releases', PATCH)


if __name__ == "__main__":
    unittest.main()
