#!/bin/bash

echo "=== opencode-termux Release Setup ==="
echo ""

# Check if gh is authenticated
if ! gh auth status &>/dev/null; then
    echo "Error: GitHub CLI not authenticated"
    echo "Run: gh auth login"
    exit 1
fi

REPO="C04-wq/opencode-termux"
VERSION="1.0.0"
ARCHIVE="opencode-termux-aarch64.tar.gz"

# Create repo if it doesn't exist
echo "Creating GitHub repo..."
gh repo create "$REPO" --private --description "OpenCode AI for Android Termux" 2>/dev/null || echo "Repo already exists"

# Upload release
echo "Creating release v${VERSION}..."
gh release create "v${VERSION}" "$ARCHIVE" \
    --title "v${VERSION}" \
    --notes "OpenCode for Android Termux (aarch64)" \
    --repo "$REPO"

echo ""
echo "Release created: https://github.com/${REPO}/releases/tag/v${VERSION}"
echo ""
echo "Now publish to npm:"
echo "  cd opencode-termux"
echo "  npm publish"
