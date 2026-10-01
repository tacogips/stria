# P10 App View Models (StriaCore/AppModel)

**Status**: Completed (session 245; accepted by the test-integrity and adversarial gates and the post-join integration review comm-003268; moved to `impl-plans/completed/` in session 245 Step 8)
**planId**: P10
**Wave**: 3 of `impl-plans/active/stria-v01-session-245-dispatch.json`
**dependsOn**: P07, P08
**Design Reference**: `design-docs/specs/design-app-ui.md` (Window Structure, Library, Left Pane, Center Pane, Right Inspector, View Models); `design-docs/specs/design-agent-integration.md#ask` (scopes); `design-docs/specs/architecture.md#package-layout`, `#testing-strategy`, `#implementation-rollout`

## Session-245 Revision

No file of this plan exists yet; this plan is a new implementation. Its
tasks, contracts and paths are unchanged.

- The view models live in `StriaCore/AppModel`, and no new target is added
  (`architecture.md#package-layout`).
- Start only after wave 2 (P07 and P08) has joined green. P10 runs in
  parallel with P09 (disjoint `writePaths`).
- Follow the overview's Common Execution Protocol and session-245
  Stabilization Protocol (rules S5-S7). Evidence logs go to
  `tmp/stria-v01-session-245/P10/`.
- `withTestDataRoot` now creates the temp root before the test body
  (P04-S1).
- A failed ask, including a CLI vendor that cannot be launched, surfaces as
  `serviceFailed`. The transcript shows the persisted error message.
  `serviceUnavailable` goes to `notice` only.

## Session-243 Notes (still valid)

The tasks, contracts and paths are unchanged from session 241; only the wave
numbering moved (wave 4 became wave 3). P08's `AskRequest` has five fields
(`question`, `context`, `retrievalQuery`, `limit`, `threadId`), and the app
always passes `retrievalQuery: nil, limit: nil`. A `serviceUnavailable`
error, for example from vendor `cursor-api`, goes to `notice` and persists
nothing.

## Intent and Context

All app state and behaviour live in testable `@MainActor @Observable` view
models in `StriaCore/AppModel`. The SwiftUI layer (P11) only binds to them.
This plan implements:

- routing between the library and the reader;
- library import progress;
- reader navigation (page jump, current outline node, last-read restore,
  search mode);
- the agent pane (scope, scope indicator, send, citation chips, history).

## Non-goals

- No SwiftUI views or `NSViewRepresentable` (P11).
- No changes to library facades. Use the P07 and P08 APIs only.
- No streaming answers.

## writePaths

- `Sources/StriaCore/AppModel`
- `Tests/StriaCoreTests/AppModel`
- `impl-plans/active/stria-10-app-view-models.md`

## sharedPaths

- `Sources/StriaCore/Library`
- `Sources/StriaCore/Agent/AskModels.swift`
- `Sources/StriaCore/Agent/CitationParser.swift`
- `Sources/StriaCore/Import/OutlineExtractor.swift`
- `Sources/StriaCore/Models`
- `Tests/StriaCoreTests/Support`

## sharedPathNotes

- `{path: "Sources/StriaCore/AppModel", intendedEdit: "directory owned by this plan"}`
- `{path: "Tests/StriaCoreTests/AppModel", intendedEdit: "directory owned by this plan"}`
- `{path: "impl-plans/active/stria-10-app-view-models.md", intendedEdit: "append to the Progress Log section only"}`
- `{path: "Sources/StriaCore/Library", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Agent/AskModels.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Agent/CitationParser.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Import/OutlineExtractor.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Models", intendedEdit: "read-only"}`
- `{path: "Tests/StriaCoreTests/Support", intendedEdit: "read-only"}`

## Contracts (consumed by P11; all `public`, `@MainActor`, `@Observable final class` unless noted)

**`AppModel.swift`**

- `enum Route: Equatable { case library, reader(docId: String) }`.
- Properties: `route`, `library: LibraryViewModel`, `reader:
  ReaderViewModel?`, `agent: AgentPaneViewModel?`.
- `init(library: StriaLibrary, debounce: Duration = .seconds(1))`.
- `func open(documentId: String) async`:
  1. `markOpened`;
  2. create the reader and the agent;
  3. `await reader.open()`;
  4. set `route = .reader`.
  On error, set `library.alert`.
- `func showLibrary() async`: `await reader?.close()` (flush and cancel the
  expansion), set `route = .library`, then `await library.refresh()`.

**`LibraryViewModel.swift`**

- `struct LibraryRow: Identifiable, Equatable { id, title, pageCount,
  importStatus, rendered: Int, ocr: OCRCounts, unavailableReason: String?,
  lastOpenedAt: Date? }`.
- Properties: `rows: [LibraryRow]` (ordered `.recents`), `alert: String?`
  and `isImporting: Bool`.
- `func refresh() async`
- `func importFiles(_ urls: [URL])`:
  - starts one task per URL that consumes `library.importEvents(at:runOCR:
    true)`;
  - `copied` refreshes and inserts the row;
  - `rendered` updates `rendered`;
  - `ocr` updates the counts;
  - `finished` with OCR `unavailable` sets `unavailableReason`, otherwise
    refreshes;
  - `failed` sets `alert` to the message.
  - Importing the same file again selects the existing row: set
    `selectedID`.
- `var selectedID: String?`
- `func runOCR(documentId: String, retryFailed: Bool) async`: calls
  `library.runOCR` with `.pending` or `.pendingAndFailed`. Sets
  `unavailableReason` when it is reported, then refreshes.
- `func waitForImports() async`: for tests; awaits the tasks.

**`ReaderViewModel.swift`**

- `enum SidebarMode: Equatable { contents, thumbnails, search }`.
- Properties:
  - document data: `documentId`, `title`, `pageCount`, `currentPage`
    (1-based), `requestedPage: Int?`, `outline: [OutlineNode]`,
    `currentOutlineNodeID: String?`, `pdfDocument: PDFDocument?`;
  - sidebar and search: `sidebarMode`, `searchQuery: String`,
    `searchResults: [SearchResultItem]`, `pagesWithoutOCR: Int`;
  - page field: `pageFieldText: String`.
- `func open() async`:
  1. load the record and `pdfDocument` from `originalURL`;
  2. `outline` comes from `library.outline`. If that is empty and the
     document is still `rendering`, use `OutlineExtractor.extract(pdfDocument)`;
  3. `requestedPage = record.lastReadPage ?? 1`;
  4. start the expansion task:
     `library.expandAllPages(documentId:concurrency: 2)`.
- `func close() async`: cancel the expansion task, then
  `flushReadingPosition()`.
- `func pageDidChange(to page: Int)`: from PDFView. Updates `currentPage`,
  `pageFieldText`, `currentOutlineNodeID`, and schedules a debounced
  `setLastReadPage`.
- `func goToPage(_ page: Int)`: clamps to `1...pageCount` and sets
  `requestedPage`.
- `func commitPageField()`: parses an Int after trimming. Non-numeric text
  restores `pageFieldText` to the current page and does nothing else.
  Numbers are clamped.
- `func nextPage()` and `func previousPage()`: no-ops at the bounds.
- `func consumeRequestedPage() -> Int?`: returns the request and clears it.
- `func submitSearch(_ query: String) async`:
  - an empty query calls `clearSearch()`;
  - otherwise call `library.search(query, documentId, limit: 100)`, store
    the results, remember the previous mode, and switch to `.search`;
  - `pagesWithoutOCR` comes from the pending and failed counts.
- `func clearSearch()`: restores the previous mode and empties the results.
- `func flushReadingPosition() async`
- Outline helpers (internal, tested):
  - node IDs are index paths such as `"0.2.1"`;
  - `currentOutlineNodeID` is the last node in document order (pre-order
    walk) whose `page != nil && page <= currentPage`, or nil.
- Debounce: every page change cancels the previous pending save task and
  starts `Task { try await Task.sleep(for: debounce); save }`.
  `flushReadingPosition` saves immediately if a save is pending.

**`AgentPaneViewModel.swift`**

- `enum AgentScope: CaseIterable { page, nearby, document }` and
  `enum HistoryMode { page, document }`.
- Properties:
  - `scope`, `scopeDescription: String` (computed), `input: String`;
  - `threadId: String?`, `transcript: [ChatMessageRecord]`, `inFlight:
    Bool`, `notice: String?`;
  - `historyMode`, `history: [ChatMessageRecord]`;
  - `suggestedQuestions: [String]`, exactly the three fixed strings in the
    design.
- `init(library:reader:)`. The view model holds the `ReaderViewModel` to
  read `currentPage` and `title`, and to request navigation.
- `scopeDescription`:
  - page: `"Sees page N"`;
  - nearby: `"Sees pages A-B"`, using the same clamping and cap as P08's
    ContextSelector (`neighborPages` and `maxImages` from
    `library.environment.config`);
  - document: `"Sees up to M relevant pages of <title>, including page N"`,
    with `M = maxImages`.
- `func send() async`:
  - ignore blank input or a request already in flight;
  - set `inFlight`, then call `library.ask(AskRequest(question: input,
    context: scope -> .page/.nearby/.document(anchor: currentPage),
    threadId: threadId))`;
  - **ok**: set `threadId`, clear `input`, then reload the transcript
    (`threadMessages`) and the history;
  - **`serviceFailed`**: set `threadId` if it was nil (generate the id
    before asking: create a UUID when `threadId` is nil and pass it), then
    reload the transcript, which shows the persisted error message;
  - **`serviceUnavailable`**: set `notice` to the message and persist
    nothing;
  - always clear `inFlight`.
- `func send(suggestion: String) async`: sets `input` and calls `send`.
- `func newChat()`: `threadId = nil`, empty transcript, clears `notice`.
- `func reloadHistory() async`: `.page` gives `history(documentId,
  currentPage)`, and `.document` gives `history(documentId, nil)`. Call it
  on page change (from P11) and after each answer.
- `func selectHistory(_ message: ChatMessageRecord) async`: set
  `threadId`, load the transcript, and `reader.goToPage(message.pageNumber)`
  when that page is non-nil.
- `func citationPages(in message: ChatMessageRecord) -> [Int]`:
  `CitationParser.markers` filtered to the open document's id, as distinct
  pages in order of appearance.

## Pitfalls

- These view models must not import SwiftUI or AppKit-only UI APIs.
  Foundation, Observation and PDFKit are fine.
- `PDFDocument` stays on the main actor inside `ReaderViewModel`. Never
  pass it to the library.
- Generate the thread id before the first ask. Without it, a failed first
  ask leaves the pane without a thread to reload.
- Do not persist "unavailable".
- Cancel the expansion task and the debounce task on `close()`, or a
  background task outlives the document.

## Tests (`Tests/StriaCoreTests/AppModel/`)

Use `@MainActor` test functions, a library built with fakes over a temp
root, documents imported through `library.importDocument(runOCR: false)`,
and OCR text set through `library.runOCR` with the fake OCR. Use
`debounce: .zero` or `.milliseconds(10)`.

`LibraryViewModelTests`:

- `importFiles` a PDF then `waitForImports` -> 1 row with `pageCount`
- importing the same file again -> still 1 row, and `selectedID` is that id
- a non-PDF -> `alert` set and no row
- fake OCR unavailable -> the row's `unavailableReason` contains the reason
- `.recents` order after `AppModel.open` -> the opened doc comes first

`ReaderViewModelTests`:

- `commitPageField` with "7" on a 5-page doc -> `requestedPage` 5
- "abc" -> `requestedPage` unchanged, field text reset
- `nextPage` at the last page -> no-op
- `open` with `lastReadPage` 3 -> `requestedPage` 3
- `pageDidChange(4)` then `flushReadingPosition` -> stored `lastReadPage` 4
- outline [A p1, B p3 [B1 p4]] -> current node at page 2 is A, at 3 is B, at 5 is B1
- `submitSearch` -> mode `.search` with results; `clearSearch` -> back to the previous mode
- `open` starts expansion -> after awaiting, the cache file for page 1 exists; `close` cancels without crashing

`AgentPaneViewModelTests`:

- scope page at page 2 -> "Sees page 2"
- nearby at page 1 with n=1 -> "Sees pages 1-2"
- send ok -> transcript has 2 messages, `threadId` set, `history(.page)` has 2
- send with fake failed -> transcript shows an assistant error message; `notice` nil
- fake unavailable -> `notice` set; transcript empty; 0 rows in the store
- `citationPages` for "[<docId> p.3] [ffffffffffffffff p.2] [<docId> p.3]" -> [3]
- `selectHistory` -> `reader.requestedPage` equals the message page

## Verification

- `swift build` -> exit 0 (`tmp/verify/P10/build.log`)
- `swift test --filter LibraryViewModelTests`, `ReaderViewModelTests` and
  `AgentPaneViewModelTests` -> pass (`tmp/verify/P10/test.log`)
- `swiftlint lint Sources/StriaCore/AppModel Tests/StriaCoreTests/AppModel` -> exit 0
- `grep -rn "import SwiftUI" Sources/StriaCore` -> no output

## Done Criteria

- [ ] All view model APIs above exist.
- [ ] Every listed behaviour is tested.
- [ ] No UI framework imports in StriaCore.

## Progress Log

### Session 245

- Implemented `AppModel`, `LibraryViewModel`, `ReaderViewModel` and `AgentPaneViewModel` in `Sources/StriaCore/AppModel/`; added 11 behavioral tests across the three named suites in `Tests/StriaCoreTests/AppModel/`. Coverage includes streamed import progress/idempotent selection/alerts/OCR unavailability/retry, recents and route lifecycle, page parsing/clamps/bounds, outline selection, last-read restore/flush, search mode, expansion start/cancel, scope descriptions, successful/failed/unavailable asks, citations and history selection.
- P10 implementation checks pass on the current combined tree: `swift build --build-tests` (exit 0, `tmp/stria-v01-session-245/P10/build-tests-shared-retry-1.log`); `swift test --filter 'LibraryViewModelTests|ReaderViewModelTests|AgentPaneViewModelTests'` (11 tests, 3 suites, 0 failures, exit 0, `tmp/stria-v01-session-245/P10/focused-final.log`); selected-file strict SwiftLint (exit 0, `tmp/stria-v01-session-245/P10/swiftlint-strict-final-2.log`); no `import SwiftUI` under `Sources/StriaCore` (exit 0, `tmp/stria-v01-session-245/P10/no-swiftui-final.log`); file-length gate (exit 0, `tmp/stria-v01-session-245/P10/line-count-final.log`). Changed Swift paths are recorded as NUL-delimited entries in `tmp/stria-v01-session-245/P10/changed-swift-files.nul`.
- A final shared-target compile briefly found a P09 CLI test macro diagnostic while that file was changing; it cleared after the required settle period, and the successful full build above compiled that test file.
- Review gates and combined-tree serial integration checks remain with downstream workflow steps; this entry records implementation evidence only.
- 2026-10-02 (session 245, Step 8 serial finalization): accepted by the test-integrity and adversarial gates and the post-join integration review (comm-003268). Combined-tree evidence in `tmp/stria-v01-session-245/join/wave-5/`: `swift build --build-tests` exit 0 (`build-tests.log`), `swift test` 120 tests in 36 suites exit 0 (`swift-test-full.log`), no `import SwiftUI` in StriaCore (`no-swiftui-in-core.log`). Moved to `impl-plans/completed/`. The Done Criteria checkboxes are kept as authored (intent snapshot); this entry records that they are met.
