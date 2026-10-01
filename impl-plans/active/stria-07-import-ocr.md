# P07 Import Coordinator, OCR Coordinator, Document Facade

**Status**: Ready (re-issued in session 245)
**planId**: P07
**Wave**: 2 of `impl-plans/active/stria-v01-session-245-dispatch.json`
**dependsOn**: P03, P04, P05 (the session-245 stabilization wave)
**Design Reference**: `design-docs/specs/design-storage.md#document-identity`, `#import-pipeline`, `#expanded-png-cache`; `design-docs/specs/design-agent-integration.md#ocr`, `#run-records`; `design-docs/specs/command.md` (import, ocr, list, show, page image, page text semantics); `design-docs/specs/architecture.md#testing-strategy`, `#implementation-rollout`

## Session-245 Revision

No file of this plan exists yet; this plan is a new implementation. Its
tasks, contracts and paths are unchanged. Start only after wave 1 (P03-P06
stabilization) has joined with `swift build --build-tests` and `swift test`
green. Follow the Common Execution Protocol and the session-245
Stabilization Protocol in `impl-plans/active/stria-00-overview.md` (rules
S5-S7 apply to every plan). Evidence logs go to `tmp/stria-v01-session-245/P07/`.

### Verified APIs to call

A read-only audit of `0082491` confirmed these. All `StriaStore` methods
are actor-isolated and synchronous `throws`, so call them with
`try await library.store.<method>`.

- `StriaLibrary.open(environment:storeOptions:) throws`. Its init is
  private. Properties: `environment`, `store`, `paths`.
- Store, documents:
  - `insertDocument(_ record: DocumentRecord)`
  - `document(id:) -> DocumentRecord?`, `document(sha256:) -> DocumentRecord?`
  - `markDocumentReady(id:outlineJSON:)`
  - `listDocuments(order:) -> [DocumentRecord]`
  - `ocrCounts(documentId:) -> OCRCounts`
  - `setLastReadPage(documentId:page:)`, `markOpened(documentId:)`
- Store, pages:
  - `insertPage(documentId:pageNumber:image:)`
  - `pageNumbers(documentId:) -> [Int]`, `pageNumbers(documentId:statuses:) -> [Int]`
  - `pageInfo(documentId:page:) -> PageInfo?`, `pageInfos(documentId:)`
  - `pageImage(documentId:page:) -> StoredPageImage?`
  - `recordOCRSuccess(documentId:page:text:vendor:model:run:)`
  - `recordOCRFailure(documentId:page:error:vendor:model:run:)`
- `DocumentIdentity.sha256Hex(of:)` and `docId(sha256Hex:)`.
- `PDFInspector.inspect(url:) -> PDFInspection { pageCount, title }`.
- `PageRenderer.render(page:dpi:maxPixelDimension:) -> CGImage`.
- `ImageCodec.encode(_:preferred:quality:) -> StoredPageImage`.
- `OutlineExtractor.extract(from:)`, `encodeJSON(_:)` and `decodeJSON(_:)`.
- `PageImageCache(paths:)`:
  - `validCachedURL(docId:page:width:height:) -> URL?`
  - `expand(docId:page:image:) -> URL`
  - `write(image:to:)`
- `RunLogWriter(paths:).append(_:) throws` and
  `SecretRedactor.truncate(_:limit:)`.

### Behaviour notes from the session-245 design corrections

- `pdf-text-layer` now returns NFKC-normalized text (P05-S1).
  `OCRTextPostProcessor.clean` still trims and strips fences for every
  vendor.
- A CLI vendor executable that cannot be launched surfaces as
  `ServiceError.failed`, not `unavailable`. That page becomes `failed`, and
  no special case is needed.
- `withTestDataRoot` now creates the temp root (0700) before the test body
  (P04-S1). `originals/`, `cache/` and `logs/` still do not exist until
  production code creates them. Do not create them in tests unless a
  fixture needs them, as the import tests do through `ensureDirectories` or
  first use.

## Session-243 Notes (still valid)

The tasks, contracts and paths are unchanged from session 241; only the wave
numbering moved (wave 3 became wave 2). Checked against the wave-1 code:

- `Sources/StriaCore/Models/ImportModels.swift` already defines
  `ImportEvent` (`copied(docId:)`, `rendered(page:total:)`,
  `ocr(OCRProgress)`, `finished(ImportResult)`, `failed(StriaError)`),
  `ImportResult`, `ImportOCROutcome`, `ImportOCRStatus`, `OCRSelection`,
  `OCRRunSummary` (with `unavailableReason`), `OCRFailure` and `OCREvent`.
  Use them as-is;
- `Library/StriaEnvironment.swift:StriaEnvironment.onRunLogFailure` and
  `clock` exist;
- `Tests/StriaCoreTests/Support/FakeOCRService.swift` supports
  `script(docId:page:_:)`, `setDefault(_:)`, `setDelay(nanoseconds:)` and
  `maxInFlight`. Its default text is `"text <docId> p<page>"`.

An OCR call with vendor `cursor-api` surfaces as
`ServiceError.unavailable` (P05 preflight). It is handled by the existing
unavailable branch, so no special case is needed here.

## Intent and Context

This plan composes the store (P03), the imaging and cache blocks (P04) and
the run log writer (P05) into the shared import and OCR pipeline. The CLI
(P09) and the app view models (P10) consume it through `StriaLibrary`
extensions. Importing must succeed even when OCR is unavailable. OCR is
per-page, resumable, retryable and bounded in concurrency.

## Non-goals

- No ask, search or history facade (P08). No CLI output (P09). No UI.
- Do not change P03/P04/P05 files. If an API you need is missing, record it
  in the Progress Log for reconciliation, and use the closest existing API.

## writePaths

- `Sources/StriaCore/Import/ImportCoordinator.swift`
- `Sources/StriaCore/OCR/OCRCoordinator.swift`
- `Sources/StriaCore/OCR/OCRTextPostProcessor.swift`
- `Sources/StriaCore/OCR/OCRDefaults.swift`
- `Sources/StriaCore/Library/StriaLibrary+Import.swift`
- `Sources/StriaCore/Library/StriaLibrary+OCR.swift`
- `Sources/StriaCore/Library/StriaLibrary+Documents.swift`
- `Sources/StriaCore/Library/LibraryResults.swift`
- `Tests/StriaCoreTests/ImportOCR`
- `impl-plans/active/stria-07-import-ocr.md`

## sharedPaths

- `Sources/StriaCore/Storage`
- `Sources/StriaCore/Library/StriaLibrary.swift`
- `Sources/StriaCore/Import/DocumentIdentity.swift`
- `Sources/StriaCore/Import/PDFInspector.swift`
- `Sources/StriaCore/Import/PageRenderer.swift`
- `Sources/StriaCore/Import/ImageCodec.swift`
- `Sources/StriaCore/Import/OutlineExtractor.swift`
- `Sources/StriaCore/Cache/PageImageCache.swift`
- `Sources/StriaCore/Integration/RunLogWriter.swift`
- `Sources/StriaCore/Integration/SecretRedactor.swift`
- `Sources/StriaCore/Models`
- `Tests/StriaCoreTests/Support`

## sharedPathNotes

- `{path: "Tests/StriaCoreTests/ImportOCR", intendedEdit: "directory owned by this plan"}`
- `{path: "impl-plans/active/stria-07-import-ocr.md", intendedEdit: "append to the Progress Log section only"}`
- `{path: "Sources/StriaCore/Storage", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Library/StriaLibrary.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Import/DocumentIdentity.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Import/PDFInspector.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Import/PageRenderer.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Import/ImageCodec.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Import/OutlineExtractor.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Cache/PageImageCache.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Integration/RunLogWriter.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Integration/SecretRedactor.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Models", intendedEdit: "read-only"}`
- `{path: "Tests/StriaCoreTests/Support", intendedEdit: "read-only"}`

## Contracts (consumed by P09 and P10)

`LibraryResults.swift`:

- `public struct PageImageResult: Sendable, Equatable { docId: String, page:
  Int, path: URL, width: Int, height: Int, cached: Bool }`

`StriaLibrary+Import.swift`:

- `public func importEvents(at url: URL, runOCR: Bool) -> AsyncStream<ImportEvent>`
- `public func importDocument(at url: URL, runOCR: Bool) async throws -> ImportResult`:
  drains the stream and returns the `finished` value, or throws the
  `failed` error.

`StriaLibrary+OCR.swift`:

- `public func ocrEvents(documentId: String, selection: OCRSelection) -> AsyncStream<OCREvent>`
- `public func runOCR(documentId: String, selection: OCRSelection) async throws -> OCRRunSummary`

`StriaLibrary+Documents.swift`:

- `listDocuments(order: DocumentOrder = .importedDescending) async throws -> [DocumentSummary]`
- `document(id: String) async throws -> DocumentRecord`: throws
  `documentNotFound`.
- `summary(of: DocumentRecord) async throws -> DocumentSummary`:
  `originalPath` is absolute (`paths.root` + relative), and the OCR counts
  come from the store.
- `outline(documentId:) async throws -> [OutlineNode]`: from `outline_json`,
  or `[]`.
- `originalURL(documentId:) -> URL`
- `pageImage(documentId:page:output: URL?) async throws -> PageImageResult`:
  - an unknown doc throws `documentNotFound`;
  - a page outside `1...pageCount`, or with no row yet, throws
    `pageNotFound`;
  - with `output`: write there with `cached = false`, and leave the cache
    untouched;
  - otherwise use `validCachedURL` (`cached = true`), or else read the BLOB
    and call `expand` (`cached = false`).
- `pageText(documentId:page:) async throws -> PageInfo`: `pageNotFound`
  when the page does not exist.
- `expandAllPages(documentId:concurrency: Int = 2) async throws -> Int`:
  - returns the number of files written;
  - skips valid cache files;
  - is bounded by a TaskGroup;
  - checks `Task.isCancelled` between pages and stops quietly when
    cancelled.
- `markOpened(documentId:) async throws` and
  `setLastReadPage(documentId:page:) async throws` pass through to the
  store.

## Import Coordinator Behaviour (`ImportCoordinator.swift`)

The work runs in an unstructured `Task` created by `importEvents`. The
stream's `onTermination` cancels that task.

1. `PDFInspector.inspect`, which throws `invalidPDF`. Then
   `DocumentIdentity.sha256Hex` and `docId`.
2. Check for an existing document:
   - **Existing by sha256 with status `ready`**: emit `finished(ImportResult(alreadyImported: true, document, ocr: .skipped with current counts))`.
     Do not copy, render or OCR.
   - **Existing by sha256 with status `rendering`** (an interrupted import):
     set `alreadyImported = true`. Make sure the original exists, re-copying
     it if missing. Render only the missing pages, using
     `store.pageNumbers(documentId:)`. Continue from step 5. OCR follows
     `runOCR`: it is not skipped, because those pages were never OCRed.
   - **Existing by id with a different sha256**: throw `idCollision`.
3. Copy to `originals/<docId>.pdf`: copy to a temp name in `originals/`,
   then `moveItem`. If the destination already exists, keep it.
4. Insert the `DocumentRecord`:
   - `importStatus .rendering`;
   - `renderDPI` and `imageFormat` from `config.render`;
   - `ocrVendor` and `ocrModel` from `config.ocr`;
   - `originalPath` relative: `"originals/<docId>.pdf"`;
   - `byteSize` from the file attributes.
   Emit `copied(docId)` only after this insert, so the row exists when the
   app opens it (addresses the Step 3 residual risk).
5. Open `PDFDocument` from the original inside the task. For each missing
   page in order, inside `autoreleasepool`:
   - `PageRenderer.render`;
   - `ImageCodec.encode(preferred: config.render.imageFormat, quality:)`;
   - `store.insertPage`;
   - emit `rendered(page, total)`.
   Check for cancellation between pages.
6. `OutlineExtractor.extract`, then `encodeJSON`, then `markDocumentReady`.
7. If `runOCR`, run `OCRCoordinator` with `.pending`, forwarding progress as
   `.ocr(progress)`. The outcome status is:
   - `unavailable` (with `reason`) when the summary has
     `unavailableReason`;
   - `partial` when `failed > 0`;
   - `completed` otherwise.
   Without `runOCR`, the status is `skipped`.
8. Emit `finished(ImportResult)`. Any `StriaError` emits `failed` and ends
   the stream. Other errors are wrapped as `ioError`. When a copy fails, no
   documents row may be left behind.

## OCR Coordinator Behaviour (`OCRCoordinator.swift`)

- Inputs: store, `PageImageCache`, `RunLogWriter` and `StriaEnvironment`.
- The document must exist (`documentNotFound`).
- Selection, mapped to store statuses:
  - `.pending` selects `[.pending]`;
  - `.pendingAndFailed` selects `[.pending, .failed]`;
  - `.pages(list)` takes exactly those pages. Every page must exist,
    otherwise `pageNotFound`.
  An empty selection returns a summary with `processed: []` and calls no
  service.
- Settings: `ServiceSettings(ocr: config.ocr)`. The prompt is
  `config.ocr.prompt ?? OCRDefaults.prompt`, the exact text from
  `design-agent-integration.md#execution`.
- Concurrency: `width = min(max(config.ocr.concurrency, 1), 8)`. Use a
  TaskGroup that seeds `width` tasks and adds one more as each finishes.
- Per page:
  1. Get the PNG URL: `validCachedURL`, or `expand(store.pageImage)`.
  2. `start = clock()`.
  3. Call `recognize`.
  4. Build an `AgentRunRecord` (`kind .ocr`, `imageCount 1`,
     `durationMs`).
- Result handling:
  - **Success**: `OCRTextPostProcessor.clean(text)`, then
    `store.recordOCRSuccess(..., run:)`.
  - **`ServiceError.failed(msg)` or any non-ServiceError error**:
    `SecretRedactor.truncate(msg)`, then `recordOCRFailure(..., run:)`.
  - **`ServiceError.unavailable(reason)`**: no record. Set the summary's
    `unavailableReason`, stop scheduling new pages, and let in-flight pages
    finish. Unprocessed pages keep their status.
  - After each committed record, call `RunLogWriter.append(run)`. If it
    throws, call `environment.onRunLogFailure?(message)` and continue.
- Progress: after each page, emit document-wide counts from
  `store.ocrCounts`.
- Summary: `processed` holds the pages that got a result (success or
  failure), sorted. The counts are document-wide after the run, and
  `failures` holds this run's failures.
- `OCRTextPostProcessor.clean`:
  - trim whitespace and newlines;
  - if the text starts with "```" and ends with "```", drop the first line
    (the fence plus an optional language tag) and the closing fence, then
    trim again.

## Pitfalls

- `PDFDocument` and `PDFPage` must not cross task or actor boundaries.
  Create them inside the import task.
- Do not hold all page images in memory. Render, encode and insert one page
  at a time.
- Never let OCR errors fail the import. The OCR outcome is reported in
  `ImportResult.ocr`.
- Do not persist an "in progress" status.
- Run log failures must never fail OCR.
- Use `environment.clock` for timestamps, never `Date()` directly, so tests
  are deterministic.

## Tests (`Tests/StriaCoreTests/ImportOCR/`)

Use `withTestDataRoot`, `makeTestEnvironment`, `SamplePDFFactory` and
`FakeOCRService`.

`ImportTests`:

- 3-page PDF with `runOCR` false -> `alreadyImported` false, `pageCount` 3, status `ready`, ocr `skipped` with pending 3; the original bytes equal the source; 3 page rows
- events -> first `copied`, then `rendered` for 1, 2 and 3 in order, then `finished`; when `copied` arrives, `store.document(id:)` is non-nil
- same file again -> `alreadyImported` true; page row count unchanged; ocr `skipped`
- non-PDF -> `invalidPDF`; no documents row and no file in `originals/`
- interrupted import (seed the document as `rendering` with only page 1 inserted, plus the original copied) -> re-import renders pages 2 and 3, status `ready`, `alreadyImported` true
- `runOCR` true with the fake default -> `completed`, done 3; `library.store.search` finds "text <docId> p2"
- fake scripted `.unavailable("environment variable X is not set")` -> import returns ocr `unavailable` with that reason; pending 3; no `agent_runs`
- one page scripted `.failure` -> `partial`, failed 1
- seeded document with the same id but a different sha -> `idCollision`

`OCRCoordinatorTests`:

- `.pending` processes only pending pages
- a failed page is skipped by `.pending`, then `.pendingAndFailed` turns it `done`
- `.pages([2])` on a done page -> re-run, and the attempt is recorded
- `concurrency` 2, delay 50 ms, 6 pages -> fake `maxInFlight == 2`
- unavailable -> statuses unchanged; `unavailableReason` set; 0 `agent_runs` rows
- every call writes one `agent_runs` row (kind `ocr`) and the JSONL line count equals the call count
- the fake returns "```\nhello\n```" -> stored text "hello"
- a 3000-character failure message -> stored `ocr_error` length 2000
- logs path replaced by a regular file (append fails) -> `onRunLogFailure` called; page still `done`

`DocumentsFacadeTests`:

- `pageImage` first call -> `cached` false and the file exists; second call -> `cached` true
- `output` -> the file is at `output` and the cache file was not created
- page 99 -> `pageNotFound`; unknown doc -> `documentNotFound`
- `listDocuments` -> absolute `originalPath` and correct counts
- `expandAllPages` -> writes `pageCount` files; a second call returns 0
- `setLastReadPage` and `markOpened` are persisted

## Verification

- `swift build` -> exit 0 (`tmp/verify/P07/build.log`)
- `swift test --filter ImportTests`, `--filter OCRCoordinatorTests` and
  `--filter DocumentsFacadeTests` -> pass (`tmp/verify/P07/test.log`)
- `swiftlint lint` on this plan's files -> exit 0
- `wc -l` -> each file is under 1000 lines

## Done Criteria

- [ ] The import and OCR facades exist with the exact signatures.
- [ ] The OCR state machine and concurrency bound are tested.
- [ ] `copied` is emitted after the documents row exists.
- [ ] Import succeeds when OCR is unavailable.

## Progress Log

### Session 245

- (worker appends entries here)
