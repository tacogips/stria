# P14: Wider macOS agent pane (default 640, min 520, max 1100)

**Status**: Completed
**planId**: P14
**dependsOn**: none (wave 1)
**Design Reference**: `design-docs/specs/design-app-ui.md#agent-pane-layout-compact-redesign-macos` ("Pane width (macOS split view)" paragraph); `design-docs/agent-chat-layout.md` (updated numbers)

## Purpose and Context

Users want a wider agent pane. Today `Sources/StriaApp/ReaderView.swift`
has `@AppStorage("readerAgentPaneWidth") private var agentPaneWidth = 520.0`
(line 22), the split pane frame
`.frame(minWidth: 480, idealWidth: max(480, agentPaneWidth), maxWidth: 800)`
(about line 108), and `SplitWidthKeeper.updateNSView` sets
`coordinator.savedAgent = max(480, agentWidth)` (about line 331).
`SplitWidthKeeper` saves a width only on a user divider drag
(`Coordinator.saveWidths`), so a user who never dragged has no stored value.

## Non-goals

- Do not change the 1000-point `agentVisible` threshold, the 760-point
  sidebar threshold, the left pane's 180/400 range or `leftPaneWidth`.
- Do not change the compact lower-half agent (`frame(height: 420)` and
  `height / 2`), the `compactPane` sheet, or `SplitWidthKeeper`'s
  attach/drag/restore logic.
- No one-off migration that rewrites the stored `UserDefaults` value.
- Do not touch `AgentPaneView.swift` (owned by P15).

## File-Level Changes

`Sources/StriaApp/ReaderView.swift` only:

1. Add three private constants for the agent pane width: min 520, default
   640, max 1100. Use a `private enum AgentPaneWidth { static let min ...
   static let ideal ... static let max ... }` at file scope, or private static
   lets on `ReaderView` that `SplitWidthKeeper` can reach (it is a separate
   `private struct` in the same file, so file-scope `private` works). Add a
   small helper that clamps a stored `Double` into `min...max`, for example
   `static func clamped(_ width: Double) -> Double`.
2. Change the `@AppStorage("readerAgentPaneWidth")` default from `520.0` to
   the 640 constant. Keep the key string exactly `readerAgentPaneWidth`.
3. Change the agent pane frame to `minWidth` = min constant,
   `idealWidth` = the clamped stored width, `maxWidth` = max constant.
4. In `SplitWidthKeeper.updateNSView`, replace `max(480, agentWidth)` with the
   same clamp (so stored values above 1100 are also capped).
5. Leave `saveAgent` as is: a drag still writes the dragged width.

## Pitfalls

- Clamping only the lower bound in the keeper while the frame clamps both
  would make the keeper fight the frame on stored values above 1100. Use the
  same helper in both places.
- Do not write the clamped value back to `agentPaneWidth` in `body` or
  `onAppear`. That would turn a read-side clamp into a migration and can
  cause view-update loops.
- `@AppStorage` defaults must be literal-compatible expressions; referencing
  a `static let` constant is fine.
- No literal `480` or `800` should remain for the agent pane. The `760` and
  `1000` thresholds and the left pane's `180`/`400` stay.

## Invariants

- Stored 360 or 480 -> opens at 520. Stored 700 -> 700. Stored 1300 -> 1100. No stored value -> 640.
- Width persistence still happens only on user drags.
- File stays under 1000 lines (currently about 412).

## Acceptance Criteria

- [ ] `grep -n "readerAgentPaneWidth" Sources/StriaApp/ReaderView.swift` shows the default as the 640 constant.
- [ ] `grep -nE "\b(480|800)\b" Sources/StriaApp/ReaderView.swift` returns no agent-pane width usage.
- [ ] The frame and `SplitWidthKeeper` both use the same clamp helper.
- [ ] Only `Sources/StriaApp/ReaderView.swift` and this plan's Progress Log change.

## Tests

StriaApp has no test target. Verify by build, lint and grep:

- No stored width -> the pane's ideal width is 640 (code inspection of the default plus the clamp).
- Stored 480 -> clamp yields 520 (code inspection; record the reasoning in the Progress Log).
- Build and lint pass.

## Verification Commands

Run in the foreground from the repository root, with `set -o pipefail` and tee to
`tmp/stria-session-867/P14/<name>.log`:

- `swift build --target StriaApp 2>&1 | tee tmp/stria-session-867/P14/build.log` -> exit 0.
- `swiftlint lint Sources/StriaApp/ReaderView.swift 2>&1 | tee tmp/stria-session-867/P14/swiftlint.log` -> "Found 0 violations" (no new ones).
- `grep -nE "\b(480|520|640|800|1100)\b" Sources/StriaApp/ReaderView.swift | tee tmp/stria-session-867/P14/grep-widths.log` -> 520/640/1100 only in the constants.

Record each exit code and log path in the Progress Log.

## Execution Protocol

- Hash the file (`shasum -a 256`) before the first edit. Re-read before each edit. Re-hash before final verification; on drift, re-read, re-apply only this plan's intent and log it.
- Edit only `Sources/StriaApp/ReaderView.swift`. In this plan file, edit only `## Progress Log`.
- No git state changes. Do not touch the user's existing uncommitted files. No emojis.

## Progress Log

- 2026-11-20: Plan created (session 867, step 4).
- 2026-11-20: Implemented P14. All four acceptance criteria are complete: the unchanged storage key defaults to `AgentPaneWidth.ideal` (640); 520/640/1100 literals occur only in the constants; both the split frame and keeper use `AgentPaneWidth.clamped`; changes are limited to ReaderView and this Progress Log. The existing initial available width uses the same 1100 constant and remains numerically unchanged. The clamp maps stored 360/480 to 520, 700 to 700, and 1300 to 1100; the default 640 remains 640. Saving remains drag-only.
- Final-source verification (moving shared tree): `swift build --target StriaApp --scratch-path /tmp/stria-p14-build` exit 0, `tmp/stria-session-867/P14/build-final.log`; `swiftlint lint Sources/StriaApp/ReaderView.swift` exit 0, `tmp/stria-session-867/P14/swiftlint-final.log`; selected-file strict SwiftLint via `tmp/stria-session-867/P14/changed-swift.nul` exit 0, `tmp/stria-session-867/P14/swiftlint-strict-final.log`; `grep -nE '\b(480|520|640|800|1100)\b' Sources/StriaApp/ReaderView.swift` exit 0, `tmp/stria-session-867/P14/grep-widths-final.log`. The isolated scratch path avoids shared build output; serial integration owns stable aggregate verification and formal review.
- 2026-11-20: Accepted. The step 7 adversarial and test-integrity reviews accepted with no findings. Integration review on the combined P13+P14+P15 tree: `swift build` exit 0 (`tmp/stria-session-867/reconcile-wave-002/build.log`); `swift test` exit 0, 249 tests in 62 suites passed (`tmp/stria-session-867/reconcile-wave-002/test.log`); `swiftlint` 0 violations (`tmp/stria-session-867/reconcile-wave-002/swiftlint.log`). Step 7b browser E2E was skipped because there is no browser surface. Step 8 moved this plan and the session-867 dispatch manifest to `impl-plans/completed/`. Open: no visual comparison against `design-docs/references/agent-pane-redesign/mockup.png` yet.
