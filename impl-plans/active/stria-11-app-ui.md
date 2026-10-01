# P11 SwiftUI App (StriaApp, product stria-app)

**Status**: Ready (re-issued in session 245)
**planId**: P11
**Wave**: 4 of `impl-plans/active/stria-v01-session-245-dispatch.json`
**dependsOn**: P10
**Design Reference**: `design-docs/specs/design-app-ui.md` (all sections, including References and Commands and Shortcuts); `design-docs/specs/architecture.md#implementation-rollout`

## Session-245 Revision

This plan is a new implementation; only the P01 stub
`Sources/StriaApp/StriaAppMain.swift` exists. Its tasks, contracts and paths
are unchanged.

- Start only after wave 3 has joined green.
- Follow the overview's Common Execution Protocol and session-245
  Stabilization Protocol (rules S5-S7). Evidence logs go to
  `tmp/stria-v01-session-245/P11/`.
- This target has no test suite. The evidence is:
  - `swift build --product stria-app`;
  - the full `swift test` (no regressions);
  - `swiftlint`;
  - the manual checklist, or a recorded "not run: headless".

## Session-243 Notes (still valid)

The tasks, contracts and paths are unchanged from session 241; only the wave
numbering moved (wave 5 became wave 4). `Sources/StriaApp/StriaAppMain.swift`
is the 10-line P01 stub (`@main struct StriaReaderApp`), which this plan
replaces. Keep the type name `StriaReaderApp`. `StriaEnvironment.live`
comes from P05 (`Sources/StriaCore/Integration/LiveServices.swift`); there
are no unavailable fallback services.

## Intent and Context

This plan implements the macOS 14 SwiftUI app after the reference readers:

- a library home view;
- a reader built from `NavigationSplitView` (left pane: Contents,
  Thumbnails or Search) and a center `PDFView` with continuous vertical
  scrolling;
- an `.inspector` agent pane on the right;
- toolbar items and menu commands.

All logic is in the P10 view models. This target contains only views,
bindings, the PDFKit wrapper and startup.

## Non-goals

- No business logic. Anything that needs a test belongs in P10. Record
  missing view model API in the Progress Log; do not add it here.
- No `.app` bundle, Info.plist or signing (see `app-distribution.md`).
- No annotations, tabs or two-up display modes.

## writePaths

- `Sources/StriaApp`
- `impl-plans/active/stria-11-app-ui.md`

## sharedPaths

- `Sources/StriaCore/AppModel`
- `Sources/StriaCore/Library`
- `Sources/StriaCore/Integration/LiveServices.swift`
- `Sources/StriaCore/Config/ConfigStore.swift`
- `Sources/StriaCore/Paths/StriaPaths.swift`

## sharedPathNotes

- `{path: "Sources/StriaApp", intendedEdit: "directory owned by this plan; replaces the P01 stub StriaAppMain.swift"}`
- `{path: "impl-plans/active/stria-11-app-ui.md", intendedEdit: "append to the Progress Log section only"}`
- `{path: "Sources/StriaCore/AppModel", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Library", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Integration/LiveServices.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Config/ConfigStore.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Paths/StriaPaths.swift", intendedEdit: "read-only"}`

## Files and Key Points

**`StriaAppMain.swift`**

- `@main struct StriaReaderApp: App`. Do not name it `StriaApp` (it clashes
  with the module name).
- Uses `@NSApplicationDelegateAdaptor`. The delegate's
  `applicationDidFinishLaunching` calls
  `NSApp.setActivationPolicy(.regular)` and
  `NSApp.activate(ignoringOtherApps: true)`.
- Startup:
  1. `StriaPaths.resolve(homeFlag: nil, environment:
     ProcessInfo.processInfo.environment, homeDirectory:
     FileManager.default.homeDirectoryForCurrentUser, currentDirectory: cwd)`;
  2. `ConfigStore.loadOrCreate`;
  3. `StriaEnvironment.live`;
  4. `StriaLibrary.open`;
  5. `AppModel`.
  A failure shows a `StartupErrorView` with the message and no crash.
- One `WindowGroup` with `.frame(minWidth: 1100, minHeight: 700)`. Commands
  are `SidebarCommands()` plus `StriaCommands`.

**`RootView.swift`**

- Switches on `appModel.route`: `LibraryView` or `ReaderView`.

**`LibraryView.swift`**

- A `List` of rows showing the title, the page count, and a status line:
  `Rendering r/N`, `OCR d/N`, a failed count, or the unavailable reason.
- Toolbar "Import" button (`Cmd-O`) opens `.fileImporter(allowedContentTypes:
  [.pdf], allowsMultipleSelection: true)` and calls
  `library.importFiles`. Each URL needs security-scoped access, which is
  harmless when unsandboxed.
- `.dropDestination(for: URL.self)` accepts PDF URLs.
- Double-click or Return opens the row through `appModel.open`.
- Context menu: "Run OCR" and "Retry Failed OCR".
- `.alert` is bound to `library.alert`.
- The empty state shows the import button and a drop hint.

**`ReaderView.swift`**

- `NavigationSplitView { LeftPaneView } detail: { PDFKitView }`, plus
  `.inspector(isPresented: $showAgent) { AgentPaneView }`. `showAgent`
  defaults to true and is persisted with `@AppStorage`.
- Toolbar:
  - a "Library" button (`Cmd-Shift-L`);
  - `PageFieldView` in the principal placement;
  - previous and next buttons;
  - an inspector toggle button.
- `.searchable(text: $reader.searchQuery, placement: .toolbar)` with
  `.onSubmit(of: .search)`, which calls `reader.submitSearch`. Clearing the
  text calls `clearSearch`.
- `.focusedSceneValue(\.reader, reader)`.
- On `currentPage` change, call `agent.reloadHistory()`.

**`LeftPaneView.swift`**

- A segmented `Picker` for Contents and Thumbnails. Search mode is shown
  while `sidebarMode == .search`.
- Contents: a recursive `OutlineGroup` or `DisclosureGroup` tree. The row
  with `currentOutlineNodeID` is highlighted. Tapping a node with a page
  calls `goToPage`. When `outline` is empty, show a "Page 1...N" list.
- Search: rows show "p. N" and the snippet. Tapping one calls `goToPage`.
  A footer reads "N pages not yet OCRed" when `pagesWithoutOCR > 0`.

**`ThumbnailListView.swift`**

- `ScrollViewReader` plus `LazyVStack`. Each row renders
  `reader.pdfDocument?.page(at:)?.thumbnail(of: CGSize(width: 120, height:
  160), for: .cropBox)` lazily in `.task`, cached in a small
  `[Int: NSImage]` dictionary held as `@State`.
- The current page is highlighted and scrolled into view when it changes.
- Tapping a row calls `goToPage`.

**`PDFKitView.swift`**

- An `NSViewRepresentable` for `PDFView`: `displayMode =
  .singlePageContinuous`, `displayDirection = .vertical`, `autoScales =
  true`, and `document = reader.pdfDocument`.
- The Coordinator observes `.PDFViewPageChanged` and calls
  `reader.pageDidChange(to: index + 1)` on the main actor.
- `updateNSView`: if `reader.consumeRequestedPage()` returns a page, call
  `go(to:)` with that page. Set the document only when its identity changed.

**`PageFieldView.swift`**

- A `TextField` bound to `pageFieldText` with the label `of N`.
  `onSubmit` calls `commitPageField`.

**`GoToPageSheet.swift`**

- A sheet with a number field (Return commits, Escape cancels). Opened
  through Go > Go to Page (`Cmd-Opt-G`).

**`AgentPaneView.swift`**

- Scope `Picker` (segmented) with `scopeDescription` below it.
- Transcript: a `ScrollView` of messages. Assistant messages show
  citation chips: buttons labelled `p. N` from `agent.citationPages`, which
  call `reader.goToPage(N)`. Error messages are styled as errors.
- Suggested question buttons appear when the transcript is empty.
- Multi-line `TextField(axis: .vertical)`. The Send button has
  `.keyboardShortcut(.return, modifiers: .command)` and is disabled while
  `inFlight`, when a `ProgressView` is shown.
- `notice` appears as an inline banner.
- "New Chat" button (`Cmd-Shift-N`).
- History section: a segmented "This page / This PDF" control and a list
  of entries. Selecting one calls `selectHistory`.

**`StriaCommands.swift` and `FocusedReader.swift`**

- A manual `FocusedValueKey` for `ReaderViewModel` (do not rely on
  `@Entry`).
- `CommandMenu("Go")`:
  - Go to Page... (`Cmd-Opt-G`);
  - Next Page (`Cmd-Opt-Down`);
  - Previous Page (`Cmd-Opt-Up`).
- View menu additions through `CommandGroup(after: .sidebar)`:
  - Show/Hide Agent (`Cmd-Opt-0`), through a focused binding or
    notification to `showAgent`;
  - Library (`Cmd-Shift-L`).
- `CommandGroup(replacing: .newItem)`: Import PDF... (`Cmd-O`).
- Commands are disabled when no reader is focused, except Import.

## Pitfalls

- Use the 1-based page everywhere in view models, and convert to PDFKit's
  0-based index only inside `PDFKitView`.
- Avoid feedback loops. Programmatic navigation goes only through
  `requestedPage` and `consumeRequestedPage`. Never set `currentPage` from
  `updateNSView`.
- Do not render cache PNGs for display. Display uses the original PDF only.
- Do not block the main actor on import or OCR. All calls are `async`, run
  in `.task` or `Task {}`.
- Keep every file under 1000 lines, with one view per file as listed.

## Verification

- `swift build --product stria-app` -> exit 0 (`tmp/verify/P11/build.log`)
- `swift build` and `swift test` -> exit 0. No regressions
  (`tmp/verify/P11/test.log`).
- `swiftlint lint Sources/StriaApp` -> exit 0 (`tmp/verify/P11/lint.log`)
- `wc -l Sources/StriaApp/*.swift` -> each file is under 1000 lines
- Manual checklist (run interactively by the reviewer or user with
  `STRIA_HOME=$(mktemp -d) swift run stria-app`; record "not run:
  headless" if no display):
  - import by button and by drop;
  - open from the library;
  - continuous scroll;
  - the page field and Cmd-Opt-G jump;
  - outline click and current-section highlight;
  - thumbnails;
  - toolbar search results in the sidebar;
  - last-read restore after going back to the library and reopening;
  - inspector toggle;
  - scope indicator;
  - Cmd-Return send showing the unavailable notice when no API key is set;
  - history mode switch.

## Done Criteria

- [ ] `stria-app` builds.
- [ ] Every view, command and shortcut in the design tables exists.
- [ ] No logic beyond bindings.
- [ ] Lint is clean.

## Progress Log

### Session 245

- (worker appends entries here)
