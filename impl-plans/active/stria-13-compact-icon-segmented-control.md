# P13: Compact size for IconSegmentedControl

**Status**: In Progress
**planId**: P13
**dependsOn**: none (wave 1)
**Design Reference**: `design-docs/specs/design-app-ui.md#agent-pane-layout-compact-redesign-macos` ("Compact `IconSegmentedControl`" paragraph)

## Purpose and Context

The macOS agent pane redesign (session 867) needs a slimmer icon segmented
control for the agent pane's tab row and scope row. `IconSegmentedControl`
(`Sources/StriaApp/IconSegmentedControl.swift`, 40 lines) currently hard-codes
30 x 22 segments. This plan adds an opt-in compact size. It is the API
contract that P15 (agent pane layout) consumes.

`Sources/StriaApp` is a macOS-only SwiftPM executable target; the Mobile
Xcode project (`Mobile/project.yml`, `sources: [StriaMobile]`) does not
compile it.

## Non-goals

- Do not change any call site (`AgentPaneView.swift`, `SearchViews.swift:24`,
  `LeftPaneView.swift:10`). P15 adopts the compact size in the agent pane.
- Do not change the regular metrics, colours, border, selection fill or
  `.fixedSize()`.
- No new view type, no new file, no StriaCore change.

## Contract (pinned for P15)

Add to `Sources/StriaApp/IconSegmentedControl.swift`:

- A nested or file-level enum named `IconSegmentedControlSize` with cases
  `regular` and `compact`, exposing the metrics as computed properties:
  `segmentWidth: CGFloat` (30 / 24), `segmentHeight: CGFloat` (22 / 18), and
  `symbolFont: Font?` (`nil` for regular so the current default symbol size
  stays exactly as it is; `.system(size: 11)` for compact).
- A stored property on `IconSegmentedControl`:
  `var size: IconSegmentedControlSize = .regular`, declared AFTER `segments`
  so the memberwise initializer is
  `IconSegmentedControl(selection:segments:size:)` with `size` optional.
  Existing calls `IconSegmentedControl(selection: ..., segments: [...])` must
  compile unchanged.
- P15 also reuses `IconSegmentedControlSize.compact.segmentWidth`,
  `.segmentHeight` and `.symbolFont` for its standalone toolbar buttons, so
  these must be `internal` (default access), not `private`.

## File-Level Changes

`Sources/StriaApp/IconSegmentedControl.swift` only:

1. Add the enum and the `size` property described above.
2. In `body`, replace the literal `30`/`22` segment frame with
   `size.segmentWidth`/`size.segmentHeight`, apply `symbolFont` to the
   `Image` only when non-nil (for example via an `if let` or a conditional
   modifier; `.font(nil)` is also acceptable because it means "inherit"), and
   use `size.segmentHeight` for the separator `Rectangle` height.
3. Keep `.help(segment.help)`, `.accessibilityLabel(segment.help)`,
   `.accessibilityAddTraits(selected ? .isSelected : [])`, `.buttonStyle(.plain)`
   and `.contentShape(Rectangle())` exactly as today, for both sizes.

Pattern to imitate: the existing `IconSegment` / `IconSegmentedControl`
structure in the same file; keep the doc-comment style (`///`).

## Pitfalls

- Applying `.font(.system(size: 11))` unconditionally would shrink
  the regular controls used in the sidebar and search. Regular must render
  identically to today.
- Putting `size` before `segments` breaks the memberwise argument order for
  every caller.
- Do not make the default `.compact`.

## Invariants

- Regular: 30 x 22 frame, 22-point separators, default symbol font.
- File stays well under 1000 lines; no new SwiftLint violations.

## Acceptance Criteria

- [ ] `IconSegmentedControlSize` with `regular`/`compact` and the three metrics exists in `Sources/StriaApp/IconSegmentedControl.swift`.
- [ ] `IconSegmentedControl` has `var size: IconSegmentedControlSize = .regular` after `segments`.
- [ ] `grep -n "30\|22" Sources/StriaApp/IconSegmentedControl.swift` shows the numbers only in the metric definitions.
- [ ] `git diff --stat` for this plan touches only `Sources/StriaApp/IconSegmentedControl.swift` and this plan's Progress Log.

## Tests

StriaApp has no test target (`Package.swift`: only `StriaCoreTests`). Verification is by build and lint:

- Existing callers unchanged -> `swift build --target StriaApp` succeeds.
- Lint -> `swiftlint lint Sources/StriaApp/IconSegmentedControl.swift` reports 0 violations.

## Verification Commands

Run in the foreground from the repository root, with `set -o pipefail` and tee to
`tmp/stria-session-867/P13/<name>.log` (`tmp/` is gitignored evidence output,
not a plan path):

- `swift build --target StriaApp 2>&1 | tee tmp/stria-session-867/P13/build.log` -> exit 0.
- `swiftlint lint Sources/StriaApp/IconSegmentedControl.swift 2>&1 | tee tmp/stria-session-867/P13/swiftlint.log` -> "Found 0 violations".

Record each exit code and log path in the Progress Log.

## Execution Protocol

- Before the first edit, record the `shasum -a 256` of the file. Re-read the file right before each edit. Re-hash it before final verification; if it changed unexpectedly (drift), re-read, re-apply only this plan's intent and log the drift.
- Edit only `Sources/StriaApp/IconSegmentedControl.swift`. In this plan file, edit only `## Progress Log`.
- No git state changes (no add, commit, stash, checkout, reset, branch or worktree). Read-only `git status`/`git diff` are fine. Leave the user's existing uncommitted files alone.
- No emojis.

## Progress Log

- 2026-11-20: Plan created (session 867, step 4).
