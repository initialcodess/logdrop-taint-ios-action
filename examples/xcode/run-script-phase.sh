#!/bin/bash
#
# LogDrop Taint — Xcode build phase.
#
# ADDING IT (once, about a minute):
#   1. Copy this file to ~/.logdrop/xcode-scan.sh and chmod +x it.
#   2. In Xcode: select the project, pick your target, open Build Phases.
#   3. + -> New Run Script Phase.
#   4. Paste:  bash "$HOME/.logdrop/xcode-scan.sh"
#   5. Drag the new phase ABOVE Compile Sources, so it runs before the build.
#   6. Leave "Based on dependency analysis" UNCHECKED. Ticked, Xcode decides the
#      inputs have not changed and skips the scan without telling you.
#
# CHECKING THAT IT RAN:
#   - Findings appear as warnings next to the offending lines, and in the issue
#     navigator (Cmd-5).
#   - The build log (Cmd-9, then "Run custom shell script 'LogDrop Taint'") ends
#     with a line like "LogDrop Taint: 9 finding(s)." That line is the proof: no
#     line at all means the phase did not run.
#   - Nothing silently fails. A missing binary, a missing key and an expired
#     licence each print their own warning.
#
# Scans your source on every build and shows findings as Xcode warnings, so a leak
# turns up next to the code that caused it while you are still writing it.
#
# It NEVER fails the build. On your own machine this is a warning layer; the gate
# belongs in CI, where --fail-on-findings blocks the merge.
#
# SETTINGS (all optional, set them in the Run Script phase if you want):
#   SCAN_PATH   which folder to scan          (default: the whole project)
#   PANEL_URL   send the report to the panel  (default: do not send)
#   BUNDLE_ID   your app id, as registered in the panel

BIN="$HOME/.logdrop/bin/logdrop-taint"
SCAN_PATH="${SCAN_PATH:-$SRCROOT}"

# The licence key: from the environment, or from a file you keep once and forget.
if [ -z "${LOGDROP_LICENSE:-}" ] && [ -f "$HOME/.logdrop/license" ]; then
  LOGDROP_LICENSE="$(cat "$HOME/.logdrop/license")"
  export LOGDROP_LICENSE
fi

if [ ! -x "$BIN" ]; then
  echo "warning: LogDrop Taint is not installed — see https://github.com/initialcodess/logdrop-taint-ios-action"
  exit 0
fi

if [ -z "${LOGDROP_LICENSE:-}" ]; then
  echo "warning: LogDrop Taint has no licence key. Put it in ~/.logdrop/license."
  exit 0
fi

REPORT="${DERIVED_FILE_DIR:-/tmp}/logdrop-taint.sarif"

# The exit code is captured rather than acted on: a finding must not stop a build
# here. `set -e` is deliberately not used for the same reason.
OUTPUT="$("$BIN" "$SCAN_PATH" --repo-root "$SRCROOT" --sarif "$REPORT" --verbose 2>&1)"
STATUS=$?

case $STATUS in
  2) echo "warning: LogDrop Taint licence is invalid or expired." ; exit 0 ;;
  3) echo "warning: LogDrop Taint config error — check .logdrop.json." ; exit 0 ;;
esac

# Turn "  [RULE] path:line — message" into a warning Xcode can click through to.
echo "$OUTPUT" | sed -n 's|^  \[\([^]]*\)\] \([^:]*\):\([0-9]*\) — \(.*\)$|\2:\3: warning: [\1] \4|p'

COUNT=$(echo "$OUTPUT" | sed -n 's/^LogDrop Taint: \([0-9]*\) finding.*/\1/p' | head -1)
echo "LogDrop Taint: ${COUNT:-0} finding(s)."

# Send it on, if a panel is configured. Silent and harmless when it is not.
if [ -n "${PANEL_URL:-}" ] && [ -f "$HOME/.logdrop/report-to-panel.sh" ]; then
  APP_NAME="${APP_NAME:-$PRODUCT_NAME}" bash "$HOME/.logdrop/report-to-panel.sh" "$REPORT" || true
fi

exit 0
