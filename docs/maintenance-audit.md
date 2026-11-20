# Maintenance audit

This document tracks the review of the installation and maintenance lifecycle. It is temporary working documentation for this pull request.

## Review checklist

- [ ] Verify executable permissions for installed launchers, updater, and manager on fresh installs and upgrades.
- [ ] Verify consistency between `install.sh`, `manager.sh`, and the installed `opencode-termux` command.
- [ ] Verify the interactive OpenCode update flow also refreshes the project manager and scripts.
- [ ] Review rollback behavior when runtime activation or smoke tests fail.
- [ ] Review uninstall behavior and ownership checks to avoid removing unrelated files.
- [ ] Run shell syntax checks and the repository's relevant CI validations.

No production behavior is changed by this checklist.
