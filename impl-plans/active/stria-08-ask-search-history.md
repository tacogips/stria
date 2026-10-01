# P08 Ask (RAG), Search Facade, History Facade, Citation Parser

**Status**: Ready (re-issued in session 243)
**planId**: P08
**Wave**: 2 of the session-243 manifest
**dependsOn**: P03, P04, P05
**Design Reference**: `design-docs/specs/design-agent-integration.md#ask` (context selection, prompt, persistence), `#run-records`; `design-docs/specs/design-storage.md#search`, `#fuzzy-retrieval-ask`, `#chat-history-queries`; `design-docs/specs/command.md` (search, ask, history); `design-docs/specs/design-app-ui.md#reader-right-inspector-agent-pane` (citation chips); `design-docs/specs/architecture.md#implementation-rollout`

## Session-243 Revision

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

- `swift build` -> exit 0 (`tmp/verify/P08/build.log`)
- `swift test --filter` for each suite above -> pass (`tmp/verify/P08/test.log`)
- `swiftlint lint` on this plan's files -> exit 0
- `wc -l` -> each file is under 1000 lines

## Done Criteria

- [ ] Ask persists every exchange that reached a model, with the anchor on
  both messages and the run row first.
- [ ] Unavailable and `noRelevantPages` persist nothing.
- [ ] The search and history facades and the citation parser exist with the
  exact signatures.

## Progress Log

- (worker appends entries here)
