# LogDrop Taint — GitHub Action

**Taint (data-flow) analysis for iOS/Swift source code.** It tracks whether data
that came from a user — or data that was meant to stay secret — travels through
your code and reaches somewhere dangerous without being sanitised.

**Your codebase never leaves the runner.** The scan runs locally. What goes into
the report is the list of findings: the rule, the file, the line — and **the
offending line plus a few lines around it**, so the problem is legible (exactly
what GitHub Code Scanning does). The whole file, the other files scanned and the
rest of your code are never sent.

If you do not want even that, set `snippets: "false"`: the report then carries only
the rule and `file:line`, and not a single line of your code leaves.

The Android counterpart is
[logdrop-taint-android-action](https://github.com/initialcodess/logdrop-taint-android-action).
Both produce the same report shape and read the same `.logdrop.json`, so a team
shipping both apps sees one kind of finding and configures it once.

## Usage

```yaml
name: Security scan
on: [pull_request]

jobs:
  taint:
    runs-on: macos-15
    permissions:
      contents: read
      security-events: write   # only if you upload to Code Scanning
    steps:
      - uses: actions/checkout@v4
      - uses: initialcodess/logdrop-taint-ios-action@v1
        with:
          license: ${{ secrets.LOGDROP_LICENSE }}
          path: Sources
          fail-on-findings: "true"
```

`macos-15` is required (Swift 6+). The analyzer is downloaded prebuilt — nothing
is compiled in your project.

## Using it without GitHub (your machine, your server)

The analyzer is **a single executable** and needs only macOS — no Xcode, no Swift
toolchain, no Homebrew. So you are not tied to GitHub Actions:

```bash
# Download it once (change the version as needed)
V=v1.24.0
curl -fsSL -O "https://github.com/initialcodess/logdrop-taint-ios-action/releases/download/$V/logdrop-taint-$V-macos-universal.tar.gz"
curl -fsSL -O "https://github.com/initialcodess/logdrop-taint-ios-action/releases/download/$V/logdrop-taint-$V-macos-universal.tar.gz.sha256"
shasum -a 256 -c "logdrop-taint-$V-macos-universal.tar.gz.sha256"   # integrity
tar -xzf "logdrop-taint-$V-macos-universal.tar.gz"

# Run it
export LOGDROP_LICENSE="LOGDROP...."
./logdrop-taint Sources --sarif report.sarif --verbose --fail-on-findings
```

Where that helps:

- **On a developer machine** — scan your own code before you push.
- **On your own build server** (Jenkins, TeamCity, Bitrise, your Mac mini): put
  the two lines above into your build step. Exit code `1` means findings.
- **In a fastlane lane or an Xcode Run Script phase** — same binary, same exit codes.
- **On a self-hosted GitHub runner** — this action works as-is and GitHub's
  per-minute billing does not apply.

The `--sarif` output is standard SARIF 2.1.0; open it in Xcode or VS Code's SARIF
viewer, or feed it into your own dashboard.

**Ready-made recipes:** [`examples/`](examples/) has working setups for CircleCI,
GitLab CI, Jenkins, Bitrise, fastlane, an Xcode build phase and a local machine —
all built on the same install script.

## Where you see the findings

All three are **free and work on every GitHub plan**:

1. **An inline box on the pull request** — the finding appears above the relevant
   line in the "Files changed" view.
2. **The job summary** — a location / rule / finding table on the run page.
3. **The CI gate** — with `fail-on-findings: "true"`, findings block the merge.

If **Code Scanning** is enabled on your repository, the SARIF is uploaded there as
well. That feature is free on public repositories and depends on GitHub's paid Code
Security licence on private ones; without a licence the step warns and moves on —
it **does not break the build**.

## Test code is skipped

Test fixtures are where fake credentials live: WordPress-iOS writes
`blog.password = "test"` in five different test helpers, and nothing in the code
distinguishes that from the real thing. Files under a `Tests`/`UITests` directory,
or named `*Tests.swift` / `*Spec.swift`, are left out by default.

It is not done quietly — the step prints what it skipped:

```
Skipped 591 test file(s). Use --include-tests to scan them.
```

A file named directly on the command line is always scanned, whatever it is called.

## What it finds

| Scenario | CWE |
|---|---|
| User, network or deep-link data reaches `WKWebView` unsanitised | CWE-79 |
| A key hardcoded in the source reaches a crypto API | CWE-321 |
| Personal data (email, phone, password, card number, PIN, SSN, passport, date of birth) is written to a log | CWE-532 |
| Personal data is stored in the clear (a local database, `UserDefaults`, Core Data) | CWE-312 |
| User or network data is interpolated into a SQL query instead of being bound | CWE-89 |
| User or network data is built into an `NSPredicate` format string instead of being passed as an argument | CWE-943 |
| Personal data or a credential is copied to the system pasteboard, which every other app can read | CWE-200 |
| A server certificate is accepted without anything having checked it | CWE-295 |

Memory and resource leaks are reported too, and are on by default — set
`leaks: "false"` to turn them off. They are a different question from the ones
above (not "did a value reach somewhere dangerous" but "was an owned thing ever
given back"), and they add roughly a quarter to the scan time.

| Scenario | CWE |
|---|---|
| Two objects hold each other strongly, so neither is ever freed | CWE-401 |
| Manually allocated memory is not released on every path out of the function | CWE-401 |

Measured on six real applications before release: two findings, both confirmed by
hand, none wrong. A body the analysis cannot model is skipped rather than guessed
at, and the scan prints how many — about 1% of them, mostly helpers using `break`
inside a loop.

What a value is also comes from the name it is read from: `cvvTextField.text` is a
CVV, while `searchTextField.text` is only user input and produces nothing — logging
your own search term is not a leak.

It follows flows across functions too, and does not report data that passed through
a sanitiser such as `escapeHTML(...)`. Sanitising is **label-specific**: escaping
HTML stops the injection but does not stop the data being personal — an escaped
email written to a log is still a finding.

## Sending reports to the LogDrop panel (optional)

If you want to track findings over time, see the binary (Layer 1) and source scans
for the same app on one screen, and carry "this is a false positive" decisions
across scans, you can send the report to the panel:

```yaml
- uses: initialcodess/logdrop-taint-ios-action@v1
  with:
    license: ${{ secrets.LOGDROP_LICENSE }}
    path: Sources
    bundle-id: com.company.app           # required when sending to the panel
    panel-url: https://panel.logdrop.io
```

**Off by default.** Without `panel-url` nothing is sent and the scan stays entirely
local.

Sending needs three things together — `panel-url`, `license` and `bundle-id`. Miss
any one and nothing is sent. **`bundle-id` must be the id registered for that
project in the panel**: an id the panel does not recognise is refused, nothing is
stored, and the step says so loudly — but it does not fail your build unless you
ask it to (see below).

Not on GitHub Actions? Every recipe under [`examples/`](examples/) ends by calling
[`examples/report-to-panel.sh`](examples/report-to-panel.sh), which does the same
POST from CircleCI, GitLab, Jenkins, Bitrise, fastlane or a laptop. It does nothing
until you set all three of `PANEL_URL`, `LOGDROP_LICENSE` and `BUNDLE_ID`. It follows
the same rule as the action: every delivery problem is a loud warning and exit 0,
and `FAIL_ON_DELIVERY_ERROR=true` turns them all into exit 1.

The analyzer itself still contacts nothing: sending is a separate step on a report
that already exists, which is what keeps "the scanner never phones home" true
wherever you run it.

When it is sent, the only thing that goes is the **SARIF**: rule id, file path, line
number and (if enabled) the code of the offending line — so the panel can show the
faulty code with the relevant line highlighted. Turn the snippets off with
`snippets: "false"`, or stop the sending altogether by leaving `panel-url` unset.

### A report that never arrives does not fail your build

**Nothing about sending breaks your build by default** — not an unreachable panel,
not a refused key, not a rejected report. A warning is emitted, `report-id` comes
back empty, and the scan result (inline annotations, job summary, exit code) is
unaffected.

That used to be split: a rejected report failed the build, an unreachable panel did
not, on the reasoning that a rejection is yours to fix. It is not always. A bundle
id deleted or renamed in the panel answers the same way. A licence moved to another
project answers the same way. None of them is something the developer whose pull
request just went red can do anything about, and the action cannot tell them apart
from a typo.

The two ways of being wrong do not cost the same. A build blocked for a reason the
team cannot fix ends with the step deleted, and then no report is ever sent again.
A report that goes missing is bad, but it blocks nobody and is answered by saying
so loudly.

If you want delivery guaranteed, set `fail-on-delivery-error: "true"` and *any*
failure to deliver becomes exit 1. One switch, no per-code table — "did the report
arrive" is the question a team can act on.

## Adapting it to your codebase

Put a `.logdrop.json` at your repository root to adapt the rules to your project.
This is how you teach the analyzer about **your** code — your sanitising function,
your field names, your logging wrapper.

```json
{
  "sanitizers":     { "makeSafe": ["user-input"], "maskEmail": ["pii"] },
  "sources":        { "nationalId": "pii", "customerEmail": "pii" },
  "sensitiveNames": { "sifre": "pii", "kartNo": "pii" },
  "sinks":          { "secret": { "rule": "SWIFT-TAINT-PII-LOG", "accepts": ["pii"] } },
  "passthrough":    ["normalise"],
  "exclude":        ["Pods/", "Generated/", "Tests/"]
}
```

| Field | What it does |
|---|---|
| `sanitizers` | Your own sanitising function; state which kind of taint it removes. No finding is produced past it. |
| `sources` | Your own personal-data fields (`nationalId` and the like). |
| `sensitiveNames` | Your own names for sensitive inputs. A value read from a name listed here counts as personal data — useful when your fields are not in English. |
| `sinks` | Your own wrapper (your logging class, say) — state which rule it maps to. |
| `passthrough` | Your own helpers that transform data but preserve taint. |
| `exclude` | Paths to skip (`Pods/` etc.). A path is skipped if it contains the fragment. |

Labels: `user-input`, `hardcoded-secret`, `pii`, `credential`.

A bad config is **not ignored silently**: an unrecognised field, rule or label is
rejected before the scan starts, and the message lists the valid ones.

## Inputs

| Input | Default | Description |
|---|---|---|
| `license` | — | **Required.** Your licence key; keep it in a secret. |
| `path` | `.` | The file or directory to scan. |
| `fail-on-findings` | `false` | Fail the step when there are findings. |
| `annotations` | `true` | Inline boxes on the pull request. |
| `snippets` | `true` | The offending line plus ±2 lines of context in the report. With `false`, no fragment of your code leaves. |
| `leaks` | `true` | Report memory and resource leaks as well as security findings. Adds roughly 25% to the scan; `false` turns it off. |
| `upload-sarif` | `true` | Attempt to upload to Code Scanning. |
| `sarif-file` | `logdrop-taint.sarif` | SARIF output path. |
| `repo-root` | `github.workspace` | The root SARIF paths are relative to. |
| `panel-url` | *(empty)* | The panel address, if reports should go to the LogDrop panel. **Empty means nothing is sent.** |
| `bundle-id` | *(empty)* | The application id. Required when `panel-url` is set. |
| `fail-on-delivery-error` | `false` | Fail the step when the report could not be sent to the panel. Off by default; see above. |
| `analyzer-version` | the version tested with this release | You should not need to change it. |

**Outputs:** `findings` (the count), `sarif-file`, `report-id` (the id the panel
filed the report under — empty when no `panel-url` was given, or when the send
failed).

## Exit codes

The three mean different things and are never conflated:

| Code | Meaning |
|---|---|
| `0` | Clean — no findings |
| `1` | Findings (only with `fail-on-findings: "true"`) |
| `2` | A licence problem (missing / invalid / expired) |
| `3` | An error in the `.logdrop.json` config file |

## Requirements

**macOS 15 or newer.** The analyzer links against Apple system libraries, so it runs
where iOS code is already built — no Xcode, no Swift toolchain, no Homebrew, and
nothing compiled in your project.

That is the one real difference from the Android analyzer, which needs only a JVM and
runs in a plain Linux container. Cloud providers bill macOS roughly ten times Linux,
and a scan takes seconds — but the difference drops to **zero** on your own Mac,
which most iOS teams already have and which this action supports as a self-hosted
runner.

## Licence

LogDrop Taint is **commercial software** and runs on a time-limited key. This
repository distributes the action and the compiled analyzer — it is not open
source, and the analyzer's source code is not in this repository.

The key is verified **offline**: the program contacts no server, does not count your
usage and reports to nobody. It warns 14 days before expiry.

To obtain a key: **satis@initialcode.io**

---
*Initial Code Software Solutions*
