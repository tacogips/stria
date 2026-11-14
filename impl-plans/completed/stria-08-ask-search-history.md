# P08 Ask (RAG), Search Facade, History Facade, Citation Parser

**Status**: Completed (session 245; accepted by the test-integrity and adversarial gates and the post-join integration review comm-003268; moved to `impl-plans/completed/` in session 245 Step 8)
**planId**: P08
**Wave**: 2 of `impl-plans/active/stria-v01-session-245-dispatch.json`
**dependsOn**: P03, P04, P05 (the session-245 stabilization wave)
**Design Reference**: `design-docs/specs/design-agent-integration.md#ask` (context selection, prompt, persistence), `#run-records`; `design-docs/specs/design-storage.md#search`, `#fuzzy-retrieval-ask`, `#chat-history-queries`; `design-docs/specs/command.md` (search, ask, history); `design-docs/specs/design-app-ui.md#reader-right-inspector-agent-pane` (citation chips); `design-docs/specs/architecture.md#testing-strategy`, `#implementation-rollout`

## Session-245 Revision

No file of this plan exists yet; this plan is a new implementation. Its
tasks, contracts and paths are unchanged. Start only after wave 1 has
joined green. It runs in parallel with P07: the two plans have disjoint
`writePaths`, and both only read P03-P05. Follow the overview's Common
Execution Protocol and session-245 Stabilization Protocol (rules S5-S7).
Evidence logs go to `tmp/stria-v01-session-245/P08/`.

### Verified APIs to call

All `StriaStore` methods are actor-isolated and synchronous `throws`, so
call them with `try await`.

- `store.search(text:documentId:limit:) -> SearchOutcome`.
- `store.fuzzyRetrieve(question:documentId:limit:) -> [PageRef]`:
  - throws `usageError` for a `limit` outside 1...100;
  - after P03-S2, returns `[]` for an empty question before checking
    `limit`.

  `ContextSelector` validates `cap` in 1...10 first, so a `cap` passed in is
  always valid.
- `store.history(documentId:page:limit:)`: throws `usageError` when
  `limit <= 0`.
- `store.threadMessages(threadId:)`, `store.persistAskExchange(_ exchange: AskExchange)`.
- `store.pageInfo(documentId:page:)`, `store.pageImage(documentId:page:)`,
  `store.document(id:)`.
- `PageImageCache(paths:).validCachedURL(docId:page:width:height:)` and
  `expand(docId:page:image:)`.
- `RunLogWriter(paths:).append(_:)` and `SecretRedactor.truncate(_:limit:)`.
- `AgentRequest.systemPrompt` is a non-optional `String`.

### Behaviour notes from the session-245 design corrections

- A CLI vendor whose executable cannot be launched surfaces as
  `ServiceError.failed`. The ask is persisted as an assistant `error`
  message and the call throws `serviceFailed` (exit 5). No special case is
  needed.
- `withTestDataRoot` now creates the temp root before the test body
  (P04-S1).
- Snippets now use LIKE-like matching: case-insensitive and not
  diacritic-insensitive (P03-S3).

## Session-243 Notes (still valid)

The tasks, contracts and paths are unchanged from session 241; only the wave
numbering moved (wave 3 became wave 2). Checked against the wave-1 code:

- `Sources/StriaCore/Agent/AgentService.swift` already defines
  `ContextPage`, `ChatTurn`, `AgentRequest` (with `systemPrompt: String`,
  non-optional) and `AgentAnswer`;
- `Models/ChatModels.swift:AskExchange` and `NewChatThread` are the
  persistence inputs for `StriaStore.persistAskExchange` (P03);
- `Tests/StriaCoreTests/Support/FakeAgentService.swift` records `requests`,
  supports `enqueue(_:)`, and by default answers
  `"answer [<docId> p.<page>]"` for the first context page.

Use these as-is. An ask with vendor `cursor-api` surfaces as
`ServiceError.unavailable` (P05 preflight). It goes through the existing
unavailable branch and persists nothing.

## Intent and Context

This plan builds the RAG ask flow. For a scope, it selects pages, expands
their images, sends the question, OCR text and images through
`AgentService`, and persists the exchange and the run. It also adds the
search and history facades used by the CLI (P09) and the app (P10), and the
citation marker parser used by the agent pane.

## Non-goals

- No import or OCR (P07). No CLI JSON (P09). No UI.
- No streaming.
- Do not modify P03, P04 or P05 files.

## writePaths

- `Sources/StriaCore/Agent/AskModels.swift`
- `Sources/StriaCore/Agent/AgentDefaults.swift`
- `Sources/StriaCore/Agent/ContextSelector.swift`
- `Sources/StriaCore/Agent/AskCoordinator.swift`
- `Sources/StriaCore/Agent/CitationParser.swift`
- `Sources/StriaCore/Library/StriaLibrary+Search.swift`
- `Sources/StriaCore/Library/StriaLibrary+Ask.swift`
- `Tests/StriaCoreTests/Ask`
- `impl-plans/active/stria-08-ask-search-history.md`

## sharedPaths

- `Sources/StriaCore/Storage`
- `Sources/StriaCore/Library/StriaLibrary.swift`
- `Sources/StriaCore/Cache/PageImageCache.swift`
- `Sources/StriaCore/Import/PageRenderer.swift`
- `Sources/StriaCore/Import/ImageCodec.swift`
- `Sources/StriaCore/Integration/RunLogWriter.swift`
- `Sources/StriaCore/Integration/SecretRedactor.swift`
- `Sources/StriaCore/Agent/AgentService.swift`
- `Sources/StriaCore/Models`
- `Tests/StriaCoreTests/Support`

## sharedPathNotes

- `{path: "Tests/StriaCoreTests/Ask", intendedEdit: "directory owned by this plan"}`
- `{path: "impl-plans/active/stria-08-ask-search-history.md", intendedEdit: "append to the Progress Log section only"}`
- `{path: "Sources/StriaCore/Storage", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Library/StriaLibrary.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Cache/PageImageCache.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Import/PageRenderer.swift", intendedEdit: "read-only; used to build test fixtures"}`
- `{path: "Sources/StriaCore/Import/ImageCodec.swift", intendedEdit: "read-only; used to build test fixtures"}`
- `{path: "Sources/StriaCore/Integration/RunLogWriter.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Integration/SecretRedactor.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Agent/AgentService.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Models", intendedEdit: "read-only"}`
- `{path: "Tests/StriaCoreTests/Support", intendedEdit: "read-only"}`

## Contracts (consumed by P09 and P10)

`AskModels.swift`:

```
public enum AskContext: Equatable, Sendable {
  case page(docId: String, page: Int), nearby(docId: String, page: Int)
  case document(docId: String, anchorPage: Int?), library
}
public struct AskRequest: Sendable { question: String; context: AskContext; retrievalQuery: String?; limit: Int?; threadId: String? }
public struct Citation: Codable, Equatable, Sendable { docId: String; title: String; page: Int; imagePath: String }
public struct AskResponse: Sendable, Equatable { threadId: String; answer: String; vendor: String; model: String?; runId: String; citations: [Citation] }
public struct SearchResultItem: Sendable, Equatable { docId, title, page, snippet, score: Double, imagePath: String, imageCached: Bool }
public struct SearchResponse: Sendable, Equatable { query: String; matchMode: MatchMode; results: [SearchResultItem] }
```

All have public memberwise inits.

`AgentDefaults.systemPrompt`: the model must answer only from the supplied
pages, say so when the pages do not contain the answer, and cite pages
exactly as `[<docId> p.<page>]`.

`CitationParser`:

- `struct CitationMarker: Equatable { docId: String, page: Int, range: Range<String.Index> }`.
- `static func markers(in text: String) -> [CitationMarker]`: Swift
  `Regex` for `\[([0-9a-f]{16}) p\.([0-9]+)\]`, returned in text order.

Library extensions:

- `search(query: String, documentId: String?, limit: Int = 10) async throws -> SearchResponse`:
  - an unknown `documentId` throws `documentNotFound`;
  - call `store.search`;
  - `imagePath` is `paths.cachedPage(docId:page:).path`, and `imageCached`
    is whether that file exists.
- `ask(_ request: AskRequest) async throws -> AskResponse`
- `history(documentId: String?, page: Int?, limit: Int = 50) async throws -> [ChatMessageRecord]`:
  an unknown doc throws `documentNotFound`.
- `threadMessages(threadId: String) async throws -> [ChatMessageRecord]`

## ContextSelector Rules

`cap = request.limit ?? config.agent.maxImages`. A `cap` outside `1...10`
is `usageError`. No more than `cap` pages are ever selected.

| Context | Pages |
| --- | --- |
| `.page(d, p)` | `[p]`. The doc must exist and `p` must be in `1...pageCount` with a page row, otherwise `pageNotFound` |
| `.nearby(d, p)` | `max(1, p-n) ... min(count, p+n)` with `n = config.agent.neighborPages`. If more than the cap, keep the pages closest to `p` (ties: lower page first), then sort ascending |
| `.document(d, anchor)` | `store.fuzzyRetrieve(question: retrievalQuery ?? question, documentId: d, limit: cap)`. If `anchor` is non-nil and missing from the result, insert it, dropping the lowest-ranked page if over the cap |
| `.library` | `fuzzyRetrieve` across all documents |

An empty result throws `noRelevantPages`. The model is not called and
nothing is persisted.

## AskCoordinator Behaviour

1. Validate that the context document exists (`documentNotFound`). Select
   the pages.
2. For each page:
   - `title` comes from the document;
   - get the PNG URL from `validCachedURL`, or `expand(store.pageImage)`;
   - `ocrText` is set only when `ocrStatus == .done`.
3. Truncation: walk the pages in order with a remaining budget of
   `config.agent.maxContextCharacters`. Each page's text is cut to the
   remaining budget, and pages after the budget is spent get `""`, not nil.
   Images are always sent.
4. History: if `threadId` is given, load `threadMessages`. Each message with
   status `ok` becomes a `ChatTurn(role, content)`. Use `threadId` as-is. If
   the thread has no rows, create it as a new thread with that id. If
   `threadId` is nil, generate a new UUID string and create a new thread.
5. Anchor and scope:

   | Context | Anchor | Scope |
   | --- | --- | --- |
   | `.page(d, p)` | `(d, p)` | `page` |
   | `.nearby(d, p)` | `(d, p)` | `nearby` |
   | `.document(d, a)` | `(d, a)` | `document` |
   | `.library` | `(nil, nil)` | `library` |

   `NewChatThread` uses the anchor and the scope.
6. Call `agentService.ask(AgentRequest(question, systemPrompt:
   config.agent.systemPrompt ?? AgentDefaults.systemPrompt, contextPages,
   history, settings: ServiceSettings(agent:)))`, timing it with
   `environment.clock`. The run record is `kind .ask`, `imageCount =
   pages.count`, with the anchor doc and page.
7. Result handling:
   - **Success**: `persistAskExchange` (status `ok`, content = answer,
     citations = the selected `PageRef`s), then `RunLogWriter.append`
     (errors go to `onRunLogFailure`), then return `AskResponse` with
     `citations` mapped to `Citation(docId, title, page, imagePath)`.
   - **`ServiceError.failed(msg)` or a non-ServiceError error**: let
     `text = SecretRedactor.truncate(msg)`. Persist with status `error`,
     content = text, and run status `failed` with error = text. Append the
     log, then throw `StriaError(code: .serviceFailed, message: text)`.
   - **`ServiceError.unavailable(reason)`**: persist nothing, write no run,
     and throw `StriaError(code: .serviceUnavailable, message: reason)`.

## Pitfalls

- Every message in an exchange carries the anchor doc and page. P03
  enforces this in `persistAskExchange`, but the coordinator must pass the
  anchor correctly.
- For `.document` scope in the app, the current page must always be
  included (the anchor).
- Never call the service when no page was selected.
- Do not reuse a `threadId` across CLI invocations: the CLI passes nil.
- Use `environment.clock` for all timestamps.

## Tests (`Tests/StriaCoreTests/Ask/`)

Fixture helper, in this plan's test dir:

- create a document through `store.insertDocument`;
- insert N pages whose images are real (`SamplePDFFactory` +
  `PageRenderer` + `ImageCodec`, or a small `CGImage` encoded with
  `ImageCodec`);
- set OCR text through `recordOCRSuccess`.

`ContextSelectorTests`:

- `.page(d, 2)` -> [2]
- `.page(d, 9)` on a 3-page doc -> `pageNotFound`
- `.nearby(d, 1)` with n=1 -> [1, 2]
- `.nearby(d, 5)` with n=5 and cap 4 on a 10-page doc -> [3, 4, 5, 6]: the closest pages, with ties going to the lower page (3 before 7)
- `.document(d, anchor: 3)` where retrieval returns [1] -> contains 1 and 3
- `.library` with two docs -> pages from the doc containing the terms
- no matches in `.library` -> `noRelevantPages`
- limit 0 -> `usageError`

`AskCoordinatorTests` (`FakeAgentService`):

- ok -> `AskResponse` has the threadId, answer and citations, and each `imagePath` exists on disk
- the recorded `AgentRequest` has `contextPages` with the OCR text and existing `pngPath`s
- after ok -> `history(d, p)` returns 2 messages (user and assistant) with the anchor; `history(d, nil)` includes them; `agent_runs` has 1 row of kind `ask`; the JSONL has 1 line
- scripted failed -> throws `serviceFailed` (exit 5); history holds the user message plus an assistant `error` message
- scripted unavailable -> throws `serviceUnavailable`; 0 messages; 0 runs
- `noRelevantPages` -> the fake records 0 requests
- second ask with the same `threadId` -> the second request's `history` has the 2 prior turns
- `maxContextCharacters` 10 with two pages of 8 characters each -> page 1 text has 8 characters, page 2 has 2

`SearchFacadeTests`:

- `imagePath` ends with `page-0002.png`; `imageCached` is false, then true after `PageImageCache.expand`
- unknown doc filter -> `documentNotFound`

`CitationParserTests`:

- "see [0123456789abcdef p.3] and [0123456789abcdef p.12]" -> 2 markers with pages 3 and 12
- "[xyz p.3]" -> none

## Verification

- `swift build --build-tests` -> exit 0 (`tmp/stria-v01-session-245/P08/logs/build-tests-final2.log`)
- `swift test --filter 'ContextSelectorTests|AskCoordinatorTests|SearchFacadeTests|CitationParserTests'` -> 7/7, exit 0 (`tmp/stria-v01-session-245/P08/logs/focused-tests-retry-2.log`)
- `xargs -0 swiftlint lint --strict --quiet --no-cache < tmp/stria-v01-session-245/P08/logs/changed-swift-files.nul` -> exit 0 (`tmp/stria-v01-session-245/P08/logs/swiftlint-strict-final.log`)
- Selected Swift files under 1000 lines -> exit 0 (`tmp/stria-v01-session-245/P08/logs/file-length.log`)

## Done Criteria

- [x] Ask persists every exchange that reached a model, with the anchor on
  both messages and the run row first.
- [x] Unavailable and `noRelevantPages` persist nothing.
- [x] The search and history facades and the citation parser exist with the
  exact signatures.

## Progress Log

### Session 245

- Implemented AskModels, AgentDefaults, ContextSelector, AskCoordinator and CitationParser, plus search, ask, history and threadMessages StriaLibrary facades.
- Context selection validates the 1...10 cap, uses retrievalQuery for fuzzy retrieval, selects nearest nearby pages with lower-page tie breaks, and preserves document anchors. Empty unanchored retrieval throws noRelevantPages.
- Ask expands valid cached page PNGs, includes OCR only for completed pages, truncates OCR text in page order to maxContextCharacters, reuses successful thread turns, and persists the run before the anchored messages through persistAskExchange. Failed calls persist a redacted/truncated error response and failed run; unavailable/noRelevantPages persist nothing. Run-log append remains best effort.
- Added plan-named suites: ContextSelectorTests, AskCoordinatorTests, SearchFacadeTests and CitationParserTests (7 tests total).
- Passing verification on the current combined tree: `swift build --build-tests` exit 0 (`tmp/stria-v01-session-245/P08/logs/build-tests-final2.log`); `swift test --filter 'ContextSelectorTests|AskCoordinatorTests|SearchFacadeTests|CitationParserTests'` exit 0, 7/7 (`tmp/stria-v01-session-245/P08/logs/focused-tests-retry-2.log`); selected-file strict SwiftLint exit 0 using `logs/changed-swift-files.nul` (`tmp/stria-v01-session-245/P08/logs/swiftlint-strict-final.log`); selected Swift file length gate exit 0 (`tmp/stria-v01-session-245/P08/logs/file-length.log`).
- Earlier verification attempts remain recorded: initial compile errors were fixed; a focused attempt found the empty-result behavior and text-budget omissions, both fixed and covered by the final run; a shared `.build` race once prevented test-bundle launch, then the rebuilt focused run passed. Logs: `build-tests-1.log`, `build-tests-2.log`, `build-tests-3.log`, `focused-tests-final.log`, `focused-tests-retry-1.log`, and `focused-tests-final2.log` under the same P08 log directory.
- Step 6 implementation is complete. Test-integrity review, adversarial review and post-join serial integration review remain downstream workflow steps; no review approval is claimed here.
- 2026-10-02 (session 245, Step 8 serial finalization): accepted by the test-integrity and adversarial gates and the post-join integration review (comm-003268). Combined-tree evidence in `tmp/stria-v01-session-245/join/wave-5/`: `swift build --build-tests` exit 0 (`build-tests.log`), `swift test` 120 tests in 36 suites exit 0 (`swift-test-full.log`), `scripts/cli-smoke.sh` SMOKE OK exit 0 (`cli-smoke.log`). Moved to `impl-plans/completed/`. The Done Criteria checkboxes are kept as authored (intent snapshot); this entry records that they are met.
