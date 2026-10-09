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
#   LOGDROP_VERSION=v1.24.2 ./install-logdrop-taint.sh
#   LOGDROP_BIN_DIR=/usr/local/bin ./install-logdrop-taint.sh
#
# Output: $LOGDROP_BIN_DIR/logdrop-taint
set -euo pipefail

VERSION="${LOGDROP_VERSION:-v1.24.2}"
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

# EXPECTED CHECKSUMS — and the whole point is WHERE this table lives.
#
# The archive used to be checked ONLY against a .sha256 downloaded from the same
# release. That proves a download did not arrive corrupt, and nothing more: whoever
# can replace the archive in a release can replace the checksum beside it, and the
# check still passes. A verifier that ships with the thing it verifies is not a
# verifier.
#
# So the expected value lives HERE, in the script the customer already pinned. Pin the
# action by commit SHA and this line is fixed at that commit: swapping the release is
# no longer enough, because the attacker would also have to change a commit you have
# named. That is why the README asks for a SHA rather than @v1.
#
# It does not defend against someone who can push to THIS repository. Nothing in a
# repository can. Pinning is what limits that, and it is the customer's move.
#
# Ported from the Android installer, which moved to this shape first; the two had
# diverged on exactly this point and iOS was the weaker half.
expected_sha() {
  case "$1" in
    v1.24.2) echo "27f9e0433a713f1b028075ada50445d6e788cf0668be1c58ec25a697e0824fdf" ;;
    *)       echo "" ;;
  esac
}
EXPECTED="$(expected_sha "$VERSION")"

# STRICT MODE, checked BEFORE anything is fetched. Advisory by default, hard gate on
# request - the same shape as --fail-on, and for the same reason: the default that
# serves the most people is the one that does not break a pipeline over something its
# owner cannot fix today. Refusing after the download would be the same answer, later.
if [ -z "$EXPECTED" ] && [ "${LOGDROP_REQUIRE_PINNED_CHECKSUM:-false}" = "true" ]; then
  echo "" >&2
  echo "  NO PINNED CHECKSUM for $VERSION, and one was required." >&2
  echo "  This installer carries checksums for the versions it shipped with. Either" >&2
  echo "  ask for a version it knows, or move to an action release that carries" >&2
  echo "  $VERSION. Nothing was downloaded." >&2
  echo "" >&2
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

# VERIFY BEFORE RUNNING. An altered binary is somebody else's code running over your
# source; a truncated one would merely crash, later and less usefully. The check is
# NEVER skipped - only its STRENGTH varies, and when it is the weaker one it says so.
actual="$(shasum -a 256 "$WORK/$ARCHIVE" | cut -d' ' -f1)"

if [ -n "$EXPECTED" ]; then
  echo "Verifying against the checksum shipped with this action (SHA-256)"
  if [ "$actual" != "$EXPECTED" ]; then
    echo "" >&2
    echo "  CHECKSUM MISMATCH — the archive was NOT what this action expects." >&2
    echo "  expected $EXPECTED" >&2
    echo "  got      $actual" >&2
    echo "  Nothing was run. Do not use this download." >&2
    echo "" >&2
    rm -f "$WORK/$ARCHIVE"
    exit 1
  fi
else
  # A version this copy of the script does not know - an older pinned action asked for
  # a newer analyzer. Falling back keeps that working, but it is a WEAKER check and
  # says so rather than letting the output imply otherwise.
  curl -fsSL --retry 3 --retry-delay 2 -o "$WORK/$ARCHIVE.sha256" "$BASE/$ARCHIVE.sha256"
  echo "Verifying integrity (SHA-256, published beside the archive)"
  ( cd "$WORK" && shasum -a 256 -c "$ARCHIVE.sha256" )

  weak="This action carries no checksum for $VERSION, so the archive was checked against the checksum published beside it. That detects a corrupt download, not a replaced one — both come from the same release. Pin an action version that knows $VERSION, or set LOGDROP_REQUIRE_PINNED_CHECKSUM=true to fail instead."
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    echo "::warning title=Weak integrity check::$weak" >&2
  else
    echo "  WARNING: $weak" >&2
  fi
fi

tar -xzf "$WORK/$ARCHIVE" -C "$WORK"
mv "$WORK/logdrop-taint" "$BIN_DIR/logdrop-taint"
chmod +x "$BIN_DIR/logdrop-taint"

echo "Installed: $BIN_DIR/logdrop-taint ($("$BIN_DIR/logdrop-taint" --version))"
