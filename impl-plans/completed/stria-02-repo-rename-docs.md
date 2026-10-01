# P02 Repository Rename, Release Paths, README and AGENTS.md

**Status**: Completed (commit `2ea8582`, session 241 wave 1; moved to `impl-plans/completed/` in session 243)
**planId**: P02
**Wave**: 1
**dependsOn**: none
**Design Reference**: `design-docs/specs/architecture.md#rename-and-repository-changes`, `#release-surfaces`; `design-docs/specs/command.md#agent-usage`; `design-docs/user-qa/app-distribution.md`

## Intent and Context

Nothing user-facing may still say KaibaViewer or kaiba-viewer. The product
is `stria` (repository `tacogips/stria`). This plan renames the non-Swift
files and documents the CLI for agents. P01 handles the Swift side in
parallel, so do not touch Swift files or `Package.swift`.

## Non-goals

- No Swift code.
- No changes to the release logic beyond names and URLs. The release
  scripts keep shipping the CLI binary only (product `stria`). Do not add
  `.app` bundling.
- Do not create `scripts/cli-smoke.sh` or `scripts/make-sample-pdf.swift`
  (P09 owns them). This plan only adds the mise task that calls the smoke
  script.

## writePaths

- `README.md`
- `AGENTS.md`
- `mise.toml`
- `scripts/build-homebrew-release.sh`
- `scripts/render-homebrew-formula.sh`
- `scripts/build-homebrew-cask-release.sh`
- `scripts/render-homebrew-cask.sh`
- `scripts/release-homebrew-cask-local.sh`
- `packaging/homebrew/README.md`
- `.ign/ign-var.json`
- `.ign/ign-files.json`
- `.claude/skills/homebrew-release/SKILL.md`
- `.claude/skills/macos-cask-release/SKILL.md`
- `.claude/skills/apple-notarization-setup/SKILL.md`
- `.codex/skills/homebrew-release/SKILL.md`
- `.codex/skills/macos-cask-release/SKILL.md`
- `.codex/skills/apple-notarization-setup/SKILL.md`
- `.github/workflows/linux-amd64-build.yml`
- `impl-plans/active/stria-02-repo-rename-docs.md`

## sharedPaths

- none

## sharedPathNotes

- `{path: ".github/workflows/linux-amd64-build.yml", intendedEdit: "delete the file"}`
- `{path: "impl-plans/active/stria-02-repo-rename-docs.md", intendedEdit: "append to the Progress Log section only"}`

## Tasks

### TASK-001: Mechanical renames

Apply these replacements in every writePath file:

- `kaiba-viewer` -> `stria`
- `KaibaViewer` -> `Stria`, except: Homebrew formula class `KaibaViewer` ->
  `Stria`; cask display `name "KaibaViewer"` -> `name "stria"`; release
  title `"KaibaViewer $release_tag"` -> `"stria $release_tag"`
- `Kaiba Viewer Swift application` -> `PDF reader with OCR-indexed page
  search and an agent pane`
- `tacogips/kaiba-viewer` -> `tacogips/stria`

`.ign/ign-var.json`:

- `EXECUTABLE_NAME`, `HOMEBREW_CASK_TOKEN` -> `stria`
- `GITHUB_REPOSITORY` -> `tacogips/stria`
- `HOMEPAGE` -> `https://github.com/tacogips/stria`
- `PROJECT_NAME` -> `stria`
- `HOMEBREW_FORMULA_CLASS` -> `Stria`
- `SWIFT_COMMAND_TYPE` -> `StriaCommand`
- `SWIFT_EXECUTABLE_TARGET` -> `StriaCLI`
- `SWIFT_LIBRARY_TARGET` -> `StriaCore`
- `DESCRIPTION` -> the new description

`.ign/ign-files.json`: replace the four scaffold Swift paths with
`Sources/StriaCLI/main.swift`, `Sources/StriaCore/Version.swift` and
`Package.swift` entries as appropriate. Drop `Command.swift` and
`CommandTests.swift` (deleted by P01). Keep valid JSON and the existing
structure.

In the scripts, change only the `product=`, `artifact_name=`,
`github_repository=` and URL/name strings. Re-read each script fully before
editing, and keep `set -euo pipefail` and all other logic unchanged.

### TASK-002: mise.toml

- `run` -> `swift run stria`.
- Add `[tasks."run:app"]` (description "Run the SwiftUI app", run `swift run stria-app`).
- Add `[tasks.smoke]` (description "Run the CLI smoke test with a temp data root", run `scripts/cli-smoke.sh`).
- Tap paths -> `../homebrew-tap/Formula/stria.rb` and `../homebrew-tap/Casks/stria.rb`.
- Keep the hooks, tools and other tasks unchanged.

### TASK-003: README.md

Rewrite README.md in concise English with no emojis. Sections:

1. Title `stria` and a one-paragraph description.
2. Requirements: macOS 14+ and the Swift 6 toolchain via `mise install`.
3. Build, test and lint: `mise run build`, `mise run test`,
   `mise run lint`, `mise run smoke`.
4. Running: `swift run stria --help` and `swift run stria-app`.
5. Data root: `~/.local/stria`, overridden by `STRIA_HOME` and `--home`,
   with the layout from `architecture.md#data-root`.
6. Configuration: the `config.json` defaults, `stria config get/set`, and
   the rule that only environment variable names are stored. Point to
   `design-docs/user-qa/default-agent-config.md`.
7. CLI for agents: the command list with one-line descriptions, plus the
   "Agent Usage" steps (search -> page image -> answer, or `stria ask`),
   copied in short form from `command.md#agent-usage`.
8. Packaging: the Homebrew formula and cask names `stria`, CLI only. The app
   is run with `swift run stria-app` (see `app-distribution.md`).
9. Design docs: a pointer to `design-docs/specs/`.

### TASK-004: AGENTS.md

Change only:

- the Project Overview sentence -> "This is `stria`, a macOS PDF reader
  with an OCR-indexed SQLite page store, an agent chat pane and an
  agent-facing JSON CLI, built with Swift Package Manager, mise-managed tools
  and tasks, Homebrew formula packaging, and optional signed Homebrew Cask
  packaging.";
- the Common Commands block: `swift run stria --help`, and add
  `swift run stria-app`.

Keep every other rule verbatim, including the response rules, the commit
policy and the skill paths.

### TASK-005: Linux workflow

Delete `.github/workflows/linux-amd64-build.yml`, because stria depends on
PDFKit, SwiftUI and ImageIO and is macOS-only. Keep `gitleaks.yml`.

## Pitfalls

- `.github/workflows/gitleaks.yml` must stay.
- Do not rename `HOMEBREW_TAP` or `HOMEBREW_TAP_DIR`.
- Do not touch `.claude/skills/swift-coding-agent` or `ios-ipados-app-deploy`
  (they contain no kaiba references).
- Shell scripts must remain executable. Check with `test -x`.

## Verification

- `grep -rIl -i kaiba --exclude-dir=.git --exclude-dir=tmp --exclude-dir=.build --exclude-dir=design-docs --exclude-dir=impl-plans --exclude-dir=Sources --exclude-dir=Tests --exclude=Package.swift .`
  -> no output (`tmp/verify/P02/grep.log`). Swift paths are excluded
  because P01 owns them.
- `bash -n scripts/*.sh` -> exit 0 (`tmp/verify/P02/bash-n.log`)
- `/usr/bin/plutil -lint .ign/ign-var.json .ign/ign-files.json` -> OK for both.
  If plutil rejects JSON syntax, use `python3 -m json.tool` when present.
- `mise tasks ls` -> lists `run:app` and `smoke` (`tmp/verify/P02/mise-tasks.log`)
- `test -x scripts/build-homebrew-release.sh` and the same for the other 4
  scripts -> exit 0
- `test ! -e .github/workflows/linux-amd64-build.yml` -> exit 0

## Done Criteria

- [ ] No kaiba strings remain in the writePaths.
- [ ] README has the Agent Usage section, the data root and the config docs.
- [ ] mise has the `run:app` and `smoke` tasks.
- [ ] The Linux workflow is removed.

## Progress Log

- 2026-10-01 P02 audit follow-up: removed the deleted Linux build workflow from `.ign/ign-files.json`; retained the gitleaks entry. Final checks passed: both ign JSON files parse via `python3 -m json.tool`, the scoped Kaiba scan is empty, and gitleaks exists while the Linux workflow is absent from the ign manifest. Logs: `ign_json_final.log`, `kaiba_scan_final.log`, and `gitleaks_retained_final.log` in `tmp/stria-v01-session-241/P02/`.

- 2026-10-01 P02 implementation: renamed the assigned README, AGENTS overview/commands, mise tasks and tap paths, release scripts/docs/skills, and ign variables/file list to stria; removed the Linux build workflow and retained gitleaks. README now documents requirements, build/test/lint/smoke, running, the data root, configuration safety, agent CLI commands and usage, packaging, and design docs. Plan checks passed: no Kaiba matches in scanned non-Swift paths; all shell scripts pass `bash -n`; `run:app` and `smoke` tasks are listed; all five release scripts remain executable; Linux workflow absent and gitleaks workflow present. `/usr/bin/plutil -lint` rejected JSON input on this host (exit 1); both ign files passed `python3 -m json.tool` (exit 0). Complete command logs are under `tmp/stria-v01-session-241/P02/` (`kaiba_scan.log`, `bash_syntax.log`, `ign_json.log`, `ign_json_fallback.log`, `mise_run_app.log`, `mise_smoke.log`, `script_modes.log`, `linux_workflow_removed.log`, `gitleaks_retained.log`).

- (worker appends entries here)
