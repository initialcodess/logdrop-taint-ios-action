#!/usr/bin/env bash
#
# LogDrop Taint installer — downloads it, VERIFIES ITS INTEGRITY, makes it runnable.
#
# Every integration other than GitHub Actions (CircleCI, GitLab, Jenkins, Bitrise,
# fastlane, your own machine) does the same three steps. Hence one script: each CI
# calls it and wraps it in its own dialect.
#
# Usage:
#   ./install-logdrop-taint.sh                 # default version, into ./bin
#   LOGDROP_VERSION=v1.24.0 ./install-logdrop-taint.sh
#   LOGDROP_BIN_DIR=/usr/local/bin ./install-logdrop-taint.sh
#
# Output: $LOGDROP_BIN_DIR/logdrop-taint
set -euo pipefail

VERSION="${LOGDROP_VERSION:-v1.24.0}"
BIN_DIR="${LOGDROP_BIN_DIR:-$PWD/bin}"
REPO="initialcodess/logdrop-taint-ios-action"

# Validate the version format: a wrong value turns into a baffling 404.
if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: LOGDROP_VERSION must look like 'v1.2.3' (got: '$VERSION')" >&2
  exit 1
fi

# macOS is required: the analyzer links against Apple system libraries. Xcode and a
# Swift toolchain are NOT needed — only the operating system.
if [ "$(uname -s)" != "Darwin" ]; then
  echo "error: LogDrop Taint requires macOS (found: $(uname -s))." >&2
  echo "       No Swift toolchain or Xcode needed, but the OS has to be macOS." >&2
  exit 1
fi

mkdir -p "$BIN_DIR"

# Skip the download if the same version is already installed (plays well with CI caches).
if [ -x "$BIN_DIR/logdrop-taint" ] && "$BIN_DIR/logdrop-taint" --version 2>/dev/null | grep -qx "${VERSION#v}"; then
  echo "LogDrop Taint ${VERSION} is already installed: $BIN_DIR/logdrop-taint"
  exit 0
fi

ARCHIVE="logdrop-taint-${VERSION}-macos-universal.tar.gz"
BASE="https://github.com/${REPO}/releases/download/${VERSION}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading: ${VERSION}"
curl -fsSL --retry 3 --retry-delay 2 -o "$WORK/$ARCHIVE" "$BASE/$ARCHIVE"
curl -fsSL --retry 3 --retry-delay 2 -o "$WORK/$ARCHIVE.sha256" "$BASE/$ARCHIVE.sha256"

# The integrity check is NEVER skipped: scanning with a truncated or altered binary
# is worse than not scanning at all — it grants false confidence.
echo "Verifying integrity (SHA-256)"
( cd "$WORK" && shasum -a 256 -c "$ARCHIVE.sha256" )

tar -xzf "$WORK/$ARCHIVE" -C "$WORK"
mv "$WORK/logdrop-taint" "$BIN_DIR/logdrop-taint"
chmod +x "$BIN_DIR/logdrop-taint"

echo "Installed: $BIN_DIR/logdrop-taint ($("$BIN_DIR/logdrop-taint" --version))"
