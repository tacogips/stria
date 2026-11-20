# P15: Compact agent pane layout (toolbar, title row, scope row, composer)

**Status**: Completed
**planId**: P15
**dependsOn**: P13 (uses `IconSegmentedControlSize` and `size:`) (wave 2)
**Design Reference**: `design-docs/specs/design-app-ui.md#agent-pane-layout-compact-redesign-macos` (items 1-4 and the "Composer sizing" table); mockup `design-docs/references/agent-pane-redesign/mockup.png` (read-only)

## Purpose and Context

The macOS agent pane spends too much height on header controls, shows a
"New Chat" title for an empty chat, and has a small composer. This plan
changes only `Sources/StriaApp/AgentPaneView.swift` (506 lines):

- Header `HStack` (lines 24-50): the tab `IconSegmentedControl`, a divider, the
  New Chat and Resume buttons.
- `tabContent` (lines 76-100): the `.chat` case shows `chatTitleBar`,
  `Divider()`, `scopePicker`, the notice, the transcript (height 32 when
  `agent.isNewChat`) and the composer.
- `chatTitleBar` (lines 104-137), `scopePicker` (lines 195-211), and the
  composer `TextEditor` frame (lines 255-257).

P13 provides `IconSegmentedControl(selection:segments:size:)` and
`IconSegmentedControlSize.compact` with `segmentWidth` (24),
`segmentHeight` (18) and `symbolFont` (`.system(size: 11)`).

## Non-goals

- Do not change `Sources/StriaCore` at all, including
  `AgentPaneViewModel.chatTitle`. It must still return "New Chat" as its
  fallback; `Mobile/StriaMobile/MobileAgentView.swift:46` and
  `Tests/StriaCoreTests/AppModel/AgentPaneViewModelTests.swift:183` depend on it.
- Do not change the History tab's `IconSegmentedControl` (page / PDF), which
  stays regular size, or `ThreadRow`, `MessageView`, `StreamingAnswerView`,
  `ControlMSendMonitor`, `modelSelector`, `selectionWarning`, or the composer's
  bottom bar.
- Do not change symbols, keyboard shortcuts (`.keyboardShortcut(.return, modifiers: .command)` on Send stays), or menu commands.
- Do not touch `IconSegmentedControl.swift` (P13) or `ReaderView.swift` (P14).

## File-Level Changes (`Sources/StriaApp/AgentPaneView.swift` only)

1. **Toolbar row** (header `HStack`):
   - Pass `size: .compact` to the tab `IconSegmentedControl`.
   - Divider height becomes `IconSegmentedControlSize.compact.segmentHeight`.
   - The New Chat (`square.and.pencil`) and Resume (`arrow.uturn.backward.circle`)
     button images get the compact `symbolFont` and a frame of
     `segmentWidth` x `segmentHeight` with `.contentShape(Rectangle())`.
   - Row padding: `.padding(.horizontal, 10)` and `.padding(.vertical, 4)`
     (was `.horizontal` default and vertical 8).
   - Keep every existing `.help`, `.accessibilityLabel`, `.disabled(agent.inFlight)` and action unchanged.
2. **Title row visibility**: add a private computed property, for example
   `private var showsChatTitle: Bool`, equal to
   `agent.currentThread != nil || agent.transcript.contains { $0.role == .user }`.
   In `tabContent`'s `.chat` case, render `chatTitleBar` and the `Divider()`
   that follows it only when `showsChatTitle` is true. Do not use
   `agent.isNewChat` for this check: it also depends on `threadId` and
   `inFlight`, and does not match exactly when `chatTitle` falls back to
   "New Chat".
3. **Compact title row** (`chatTitleBar`): title font `.subheadline.weight(.semibold)`,
   `.lineLimit(1)`, `.truncationMode(.tail)`, keep `.help(agent.chatTitle)`.
   The `.foregroundStyle(agent.threadId == nil ? .secondary : .primary)` may
   stay. Vertical padding 4 (was 8). Keep the retitle button, spinner and `p.N`
   flag button with their help, labels and enablement unchanged.
4. **Scope row** (`scopePicker`): a single `HStack(spacing: 8)` containing the scope
   `IconSegmentedControl` with `size: .compact`, then
   `Image(systemName: "info.circle")` with the compact `symbolFont`,
   `.foregroundStyle(.secondary)`, `.help(agent.scopeDescription)` and
   `.accessibilityLabel(agent.scopeDescription)`, then `Spacer()`. Remove the
   outer `VStack` and the visible `Text(agent.scopeDescription)`. Padding:
   horizontal 12, vertical 4.
5. **Composer** `TextEditor` frame:
   `minHeight: 180`, `idealHeight: agent.isNewChat ? 280 : 240`,
   `maxHeight: agent.isNewChat ? .infinity : 360`. Keep the transcript's
   `.frame(height: agent.isNewChat ? 32 : nil)` unchanged.
6. Update the struct's doc comment if it no longer matches (it mentions only
   Chat and History). Keep the change to one line.

Patterns to imitate: the existing button style in the header
(`AgentPaneView.body` New Chat button: `.buttonStyle(.plain)`, `.help`,
`.accessibilityLabel`), and `IconSegmentedControl` usage at `AgentPaneView.swift:25`.

## Pitfalls

- The literal string "New Chat" must not appear as rendered text in this
  file. The only allowed occurrence is the New Chat button's
  `.accessibilityLabel("New Chat")`, which stays: it labels the button, not
  a title. Do not remove that label.
- Do not make both the transcript and the editor flexible for a new chat;
  the 32-point transcript frame prevents layout loops.
- An outer `.help` on the scope row would be hidden by each segment's own
  tooltip. Put the description on the info icon only.
- Do not add `.keyboardShortcut` to the toolbar buttons. Shortcuts are handled
  by the reader monitor and the menu commands, and adding them here would
  register them twice.
- The file must stay under 1000 lines (expect about 505).

## Invariants

- New chat (no thread, empty transcript) -> no title row and no divider under it; the toolbar, scope row, a 32-point transcript and the composer filling the rest.
- After the first question is sent (provisional user message in the transcript) -> the title row appears with the question's first line.
- Thread reopened from History -> the title row shows the thread title.
- Every toolbar and scope control keeps a tooltip and an accessibility label.

## Acceptance Criteria

- [ ] `grep -n '"New Chat"' Sources/StriaApp/AgentPaneView.swift` shows only the `accessibilityLabel("New Chat")` line.
- [ ] `grep -n "size: .compact" Sources/StriaApp/AgentPaneView.swift` shows exactly 2 hits (tabs, scope).
- [ ] `grep -n "scopeDescription" Sources/StriaApp/AgentPaneView.swift` shows only `.help` and `.accessibilityLabel` uses (no `Text(`).
- [ ] The TextEditor frame matches the numbers in File-Level Change 5.
- [ ] Only `Sources/StriaApp/AgentPaneView.swift` and this plan's Progress Log change.

## Tests

No StriaApp test target exists. StriaCore is untouched, so the existing
`AgentPaneViewModelTests` (including the `chatTitle == "New Chat"` expectation
at line 183) must still pass unchanged:

- Unchanged chatTitle tests -> `swift test --filter AgentPaneViewModelTests` passes.
- Build with P13's API -> `swift build --target StriaApp` exit 0.

## Verification Commands

Run in the foreground from the repository root, with `set -o pipefail` and tee to
`tmp/stria-session-867/P15/<name>.log`:

- `swift build --target StriaApp 2>&1 | tee tmp/stria-session-867/P15/build.log` -> exit 0.
- `swiftlint lint Sources/StriaApp/AgentPaneView.swift 2>&1 | tee tmp/stria-session-867/P15/swiftlint.log` -> "Found 0 violations" (no new ones).
- `swift test --filter AgentPaneViewModelTests 2>&1 | tee tmp/stria-session-867/P15/test-focused.log` -> all pass.
- `grep -n '"New Chat"\|size: .compact\|scopeDescription' Sources/StriaApp/AgentPaneView.swift | tee tmp/stria-session-867/P15/grep.log` -> matches the acceptance criteria.
- `wc -l Sources/StriaApp/AgentPaneView.swift` -> under 1000.

Record each exit code and log path in the Progress Log.

## Execution Protocol

- Start only after P13 is complete (`IconSegmentedControlSize` exists). If it is missing, stop and log a blocker; do not add it here.
- Hash the file (`shasum -a 256`) before the first edit. Re-read before each edit. Re-hash before final verification; on drift, re-read, re-apply only this plan's intent and log it.
- Edit only `Sources/StriaApp/AgentPaneView.swift`. In this plan file, edit only `## Progress Log`.
- No git state changes. Do not touch the user's existing uncommitted files. No emojis.

## Progress Log

- 2026-11-20: Plan created (session 867, step 4).
- 2026-11-20: Implemented compact toolbar and scope controls, conditional compact title, and composer sizing. All five acceptance criteria are met by source inspection; the file has 519 lines. Source SHA-256: `6e462ac4b95ed89641154b003ecba2f1187d2ae66c74685b8cda19943c0733d8`.
- Verification on the shared tree with isolated `/tmp/stria-p15-build`: `swift build --scratch-path /tmp/stria-p15-build --target StriaApp` exit 0 (`tmp/stria-session-867/P15/build.log`); `swift test --scratch-path /tmp/stria-p15-build --filter AgentPaneViewModelTests` exit 0, 6 tests passed (`tmp/stria-session-867/P15/test-focused.log`).
- `swiftlint lint Sources/StriaApp/AgentPaneView.swift` exit 0, no violations (`tmp/stria-session-867/P15/swiftlint.log`); strict selected-file lint exit 0 (`tmp/stria-session-867/P15/swiftlint-strict.log`, manifest `changed-swift.nul`). Grep and line count exit 0 (`tmp/stria-session-867/P15/grep.log`, `lines.log`).
- Formal review, combined-tree checks and visual comparison are pending integration.
- 2026-11-20: Accepted. The step 7 adversarial and test-integrity reviews accepted with no findings. Integration review on the combined P13+P14+P15 tree: `swift build` exit 0 (`tmp/stria-session-867/reconcile-wave-002/build.log`); `swift test` exit 0, 249 tests in 62 suites passed (`tmp/stria-session-867/reconcile-wave-002/test.log`); `swiftlint` 0 violations (`tmp/stria-session-867/reconcile-wave-002/swiftlint.log`). Step 7b browser E2E was skipped because there is no browser surface. Step 8 updated `README.md` and moved this plan and the session-867 dispatch manifest to `impl-plans/completed/`. Open: no visual comparison against `design-docs/references/agent-pane-redesign/mockup.png` yet.
