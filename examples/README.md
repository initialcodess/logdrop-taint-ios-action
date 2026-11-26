# Integration recipes

LogDrop Taint is **not tied to GitHub.** The analyzer is a single executable and
needs only macOS — no Xcode, no Swift toolchain, no Homebrew.

## The model: the same three steps everywhere

```
1. DOWNLOAD  →  once, per version (cacheable)
2. VERIFY    →  SHA-256; a corrupt or altered binary never scans
3. RUN       →  the exit code makes the decision
```

The first two live in [`install-logdrop-taint.sh`](install-logdrop-taint.sh), and
every recipe below calls it. On GitHub Actions you do not even need that — the
action does both for you.

## Getting the scripts

The recipes call [`install-logdrop-taint.sh`](install-logdrop-taint.sh) and
[`report-to-panel.sh`](report-to-panel.sh) as `bash examples/...`. Those two files live in
the action repository, **not in yours**, so a recipe copied on its own fails at its first
step. Put them in your repository at `examples/` before using any recipe except Xcode
(which has [its own install step](#in-xcode)). From your repository root:

```bash
REF=v1.26.0   # a release tag; use a full commit hash to pin harder
BASE="https://raw.githubusercontent.com/initialcodess/logdrop-taint-ios-action/$REF/examples"
mkdir -p examples
curl -fsSL -o examples/install-logdrop-taint.sh "$BASE/install-logdrop-taint.sh"
curl -fsSL -o examples/report-to-panel.sh "$BASE/report-to-panel.sh"
chmod +x examples/*.sh
git add examples/install-logdrop-taint.sh examples/report-to-panel.sh
```

Commit them. The installer carries a table of expected checksums, so fetching it at a
commit you named fixes what it will accept. The local recipe (`local/scan.sh`) and the
fastlane recipe expect the same layout: the two scripts in `examples/`. Copy
`local/scan.sh` to `examples/local/scan.sh`; the fastlane lane goes in your own
`fastlane/Fastfile`, which sits at your repository root next to `examples/`.

## Sending the report to the panel

Optional, and off until you switch it on. Every recipe here ends by calling
[`report-to-panel.sh`](report-to-panel.sh), and the step is safe to leave in place:
with nothing configured it prints one line and does nothing.

Three variables, and you need all three:

| Variable | What it is |
|---|---|
| `PANEL_URL` | Your panel's address |
| `LOGDROP_LICENSE` | Your key — already required for the scan itself |
| `BUNDLE_ID` | Your application's bundle id, **as registered in the panel** |

Set them wherever your CI keeps configuration and reports start arriving; no edit to
the recipe. Miss one and nothing is sent, quietly — so if the dashboard stays empty,
check that all three are actually reaching the job.

**The bundle id must be registered for that project in the panel.** One the panel
does not recognise is refused outright and nothing is stored. The step says so loudly
and, by default, still exits 0; set `FAIL_ON_DELIVERY_ERROR=true` to make a refusal
fail the step.

**The analyzer itself never contacts anything.** It verifies its licence offline,
counts no usage and does not report that it ran. Sending is a separate step, on a
report that already exists, run by you — which is why it is a script you can read
rather than a flag inside the binary.

**A report that never arrives does not fail your build, unless you ask.** By default
every delivery problem — a report the panel refuses (the usual cause is a `BUNDLE_ID`
not registered for your project), a refused key, an unreachable panel, a panel under
maintenance — prints a loud warning and the step exits 0. The scan's exit code already
said what it found, and a problem the developer who pushed the commit cannot fix must
not turn their build red.

The cost of that default is that a report can go missing while the pipeline stays
green. If you want delivery guaranteed, set `FAIL_ON_DELIVERY_ERROR=true` for the step:
then any failure to deliver exits 1. (The GitHub Action's equivalent is
`fail-on-delivery-error: "true"`.)

Which customer a report belongs to comes from your **licence key**, not from
anything the recipe sends.

## Exit codes — the contract every integration rests on

| Code | Meaning | What CI should do |
|---|---|---|
| `0` | Clean | Carry on |
| `1` | Findings (with `--fail-on-findings`; `note`-level findings never cause it) | Fail the build, block the pull request |
| `2` | Licence missing / invalid / expired | Fail, but DO NOT say "your code has a vulnerability" |
| `3` | An error in `.logdrop.json` | Fail, fix the config file |

Telling `1` and `2` apart matters: a developer whose licence lapsed will go looking
in entirely the wrong place if you tell them their code is insecure.

## The recipes

| System | File | Note |
|---|---|---|
| **GitHub Actions** | [main README](../README.md) | The action does everything, download and verification included |
| **CircleCI** | [`circleci/config.yml`](circleci/config.yml) | Needs a macOS executor (on paid plans) |
| **GitLab CI** | [`gitlab/.gitlab-ci.yml`](gitlab/.gitlab-ci.yml) | Needs a macOS runner; your own Mac is free |
| **Jenkins** | [`jenkins/Jenkinsfile`](jenkins/Jenkinsfile) | An agent labelled `macos` |
| **Bitrise** | [`bitrise/bitrise.yml`](bitrise/bitrise.yml) | Already a macOS stack; nothing extra needed |
| **fastlane** | [`fastlane/Fastfile`](fastlane/Fastfile) | Run it before the build |
| **Xcode** | [`xcode/run-script-phase.sh`](xcode/run-script-phase.sh) | Findings appear as Xcode warnings — [setup below](#in-xcode) |
| **Your own machine** | [`local/scan.sh`](local/scan.sh) | Scan your code before you push |

## Where the licence key goes

Always in the **`LOGDROP_LICENSE` environment variable**, and always sourced from
that system's secret store:

| System | Where |
|---|---|
| GitHub Actions | Repository secrets |
| CircleCI | Project Settings → Environment Variables |
| GitLab | Settings → CI/CD → Variables (tick **Masked**) |
| Jenkins | Credentials → Secret text |
| Bitrise | Secrets |
| Local | `export LOGDROP_LICENSE=...` or `~/.logdrop/license` |

Do not write the key into a configuration file: command-line arguments can show up
in run logs and in the process list, which is why every recipe here uses the
environment variable.

## The macOS requirement

The analyzer runs on macOS because it links against Apple system libraries. In
practice that is not a constraint: iOS source is already built on macOS, so the
machine is one you already have.

**A note on cost:** cloud providers bill macOS noticeably higher than Linux (~10x
on GitHub). A scan takes seconds, so the extra is small — and it drops to **zero**
if you use your own Mac as a runner, which most iOS teams already have.

## In Xcode

The scan runs on every build and findings appear as warnings against the lines that
caused them, so you see a leak while you are still writing it.

**Install the analyzer first.** The phase only runs it; it expects the binary at
`~/.logdrop/bin/logdrop-taint` and, to send reports, the script at
`~/.logdrop/report-to-panel.sh`. With no binary the build log gets
`warning: LogDrop Taint is not installed` and the build carries on; with no
`report-to-panel.sh` the panel step is skipped without a word. Once, in a terminal:

```bash
REF=v1.26.0   # a release tag; use a full commit hash to pin harder
BASE="https://raw.githubusercontent.com/initialcodess/logdrop-taint-ios-action/$REF/examples"
mkdir -p "$HOME/.logdrop"
curl -fsSL -o "$HOME/.logdrop/install-logdrop-taint.sh" "$BASE/install-logdrop-taint.sh"
curl -fsSL -o "$HOME/.logdrop/xcode-scan.sh" "$BASE/xcode/run-script-phase.sh"
curl -fsSL -o "$HOME/.logdrop/report-to-panel.sh" "$BASE/report-to-panel.sh"   # only to send reports
LOGDROP_BIN_DIR="$HOME/.logdrop/bin" bash "$HOME/.logdrop/install-logdrop-taint.sh"
chmod +x "$HOME/.logdrop/xcode-scan.sh"
```

Then:

1. `~/.logdrop/xcode-scan.sh` is already in place from the commands above.
2. In Xcode, select the project, pick your target, open **Build Phases**.
3. **+** → **New Run Script Phase**.
4. Paste: `bash "$HOME/.logdrop/xcode-scan.sh"`
5. Drag the phase **above Compile Sources**, so it runs before the build.
6. Leave **Based on dependency analysis** unticked. Ticked, Xcode decides the inputs
   have not changed and skips the scan without telling you.

Put your key in `~/.logdrop/license` once and the phase finds it; there is no key to
paste into Xcode.

### Knowing it ran

- Warnings appear next to the code, and in the issue navigator (⌘5).
- The build log (⌘9 → *Run custom shell script 'LogDrop Taint'*) ends with
  `LogDrop Taint: N finding(s).` **That line is the proof.** No line at all means the
  phase did not run.
- Nothing fails silently: a missing binary, a missing key and an expired licence each
  print their own warning.

### It never fails your build

On your own machine this is a warning layer. The gate belongs in CI, where
`--fail-on-findings` blocks the merge. A scan that broke the build every time you
typed a half-finished line would be turned off within a day.

### Scanning less

The whole project is scanned by default — minus its test code, which the analyzer
skips and says so. On a large project that is still noticeable on every build, so
point it at a folder instead:

```
SCAN_PATH="$SRCROOT/Sources" bash "$HOME/.logdrop/xcode-scan.sh"
```

### Sending to the panel from Xcode — usually don't

The phase can send its report, if you give it `PANEL_URL` and `BUNDLE_ID`. It is off
by default, and that is the recommendation:

```
PANEL_URL="https://panel.example.com" BUNDLE_ID="com.company.app" \
  bash "$HOME/.logdrop/xcode-scan.sh"
```

Turned on, **every build** publishes your working copy — half-finished code, code you
are about to delete, an experiment. Your colleagues open the panel and ask why it is
red. The panel should hold what the team agreed on, and that comes from committed
code through CI, not from somebody's editor.

Worth turning on in one case: you work alone, you have no CI, and the panel is the
only place you want history.
