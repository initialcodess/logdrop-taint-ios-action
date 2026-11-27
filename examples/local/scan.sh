#!/usr/bin/env bash
#
# Scanning on a developer machine — check your own code before you push.
#
#   export LOGDROP_LICENSE="LOGDROP...."
#   ./examples/local/scan.sh Sources
#
# No CI needed at all. Same binary, same rules, same exit codes.
#
# GET THE TWO SCRIPTS FIRST. This script calls ../install-logdrop-taint.sh and
# ../report-to-panel.sh. They live in the action repository, not in yours:
# copy them into your repository at those paths (or fetch them at the commit you pin).
# Commands: examples/README.md, section "Getting the scripts".
#
# SENDING TO THE PANEL (optional) — three variables, and all three are needed:
#
#   PANEL_URL        your panel's address
#   LOGDROP_LICENSE  your key (already required for the scan)
#   BUNDLE_ID        your application's bundle id, AS REGISTERED IN THE PANEL
#
# Miss any one and nothing is sent: the step prints a line and stays green,
# which is easy not to notice. A report the panel refuses (a BUNDLE_ID it does
# not recognise for this project, say) is a loud warning, but the step still
# exits 0. Set FAIL_ON_DELIVERY_ERROR=true to make any failed delivery fail it.
# On a laptop you usually set none of them and the report simply stays here.
set -euo pipefail

TARGET="${1:-.}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Install the analyzer (skipped if already installed).
LOGDROP_BIN_DIR="${LOGDROP_BIN_DIR:-$HOME/.logdrop/bin}"
export LOGDROP_BIN_DIR
"$HERE/../install-logdrop-taint.sh"

echo
# With `set -e` a non-zero exit ends the script immediately — and finding something
# is exactly a non-zero exit. We turn it off around this call so the code can be
# read and acted on.
set +e
"$LOGDROP_BIN_DIR/logdrop-taint" "$TARGET" \
  --sarif "logdrop-taint.sarif" \
  --verbose \
  --fail-on-findings
status=$?
set -e

# Send it on, if a panel is configured. Nothing happens without PANEL_URL, so this
# line is harmless on a laptop that only ever scans locally.
"$HERE/../report-to-panel.sh" logdrop-taint.sarif

# The exit codes mean different things — say which one it is in plain language.
case $status in
  0) echo; echo "Clean: no findings." ;;
  1) echo; echo "Findings. Full report: logdrop-taint.sarif"
     echo "You can open the SARIF with VS Code's 'SARIF Viewer' extension." ;;
  2) echo; echo "Licence problem. Is LOGDROP_LICENSE set, and has it expired?" ;;
  3) echo; echo "There is an error in your .logdrop.json (see the message above)." ;;
esac
exit $status
