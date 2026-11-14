# P03 SQLite Store, Migrations, Search, Chat and Agent Runs

**Status**: Completed (session 245; accepted by the test-integrity and adversarial gates and the post-join integration review comm-003268; moved to `impl-plans/completed/` in session 245 Step 8)
**planId**: P03
**Wave**: 1 of `impl-plans/active/stria-v01-session-245-dispatch.json` (stabilization wave)
**dependsOn**: none in this manifest (builds on completed P01, commit `2ea8582`; the code under review is in commit `0082491`)
**Design Reference**: `design-docs/specs/design-storage.md` (all sections, especially `#fuzzy-retrieval-ask` and `#search`); `design-docs/specs/design-agent-integration.md#ocr` (state machine), `#persistence`; `design-docs/specs/architecture.md#testing-strategy`, `#implementation-rollout`

## Session-245 Stabilization (authoritative for this run)

### Intent

Commit `0082491` already contains every P03 file listed below, and all seven
P03 suites exist. That code is not yet accepted. This run does not rewrite
it. The job is to:

- fix the one failing P03 test without weakening it;
- close the gaps that a read-only audit found between this plan's original
  text (the sections below this one) and the code;
- pass the test-integrity and adversarial review gates.

The original sections below stay the requirement baseline. Where this
section differs from them, this section wins.

Follow the Common Execution Protocol and the session-245 Stabilization
Protocol in `impl-plans/active/stria-00-overview.md`. Evidence logs go to
`tmp/stria-v01-session-245/P03/`.

### Current API (verified by reading the code; do not change these signatures)

- `public actor StriaStore`:
  - `init(databaseURL: URL, options: StoreOptions = .init(), clock: @escaping @Sendable () -> Date = { Date() }) throws`
  - `public let searchBackend: SearchBackend`
  - `search(text:documentId:limit:) throws -> SearchOutcome`
  - `fuzzyRetrieve(question:documentId:limit:) throws -> [PageRef]`
  - `history(documentId:page:limit:)`, `threadMessages(threadId:)`, `persistAskExchange(_:)`, `agentRuns(documentId:)`
  - the document and page methods in `StriaStore+Documents.swift` and `StriaStore+Pages.swift`
- `public struct StriaLibrary: Sendable`:
  - `static func open(environment: StriaEnvironment, storeOptions: StoreOptions = .init()) throws -> StriaLibrary`
  - `environment`, `store`, `paths`
- `enum SearchQueryBuilder` (internal): `trigrams(question:) -> TrigramTerms`, `swiftSnippet(text:term:)`, `likePattern(term:)`, `ftsMatchExpression(terms:)`

### Tasks

**P03-S1. Correct the trigram-cap test without weakening it.**

- File: `Tests/StriaCoreTests/Storage/SearchQueryBuilderTests.swift`, line 11.
- Why it fails: the test expects 64 trigrams for `String(repeating:
  "abcdef ", count: 20)`, but that input has only 4 distinct trigrams. The
  design rule (`design-storage.md#fuzzy-retrieval-ask`) is: de-duplicate
  across the whole question first, then cap at 64. The builder
  (`Sources/StriaCore/Storage/SearchQueryBuilder.swift:trigrams(question:)`)
  already does this. The test is the defect.
- Replace that one assertion with two:
  - the repeated input yields exactly `["abc", "bcd", "cde", "def"]`;
  - a question with more than 64 distinct trigrams yields exactly 64
    trigrams. Use, for example, one token made of 80 distinct CJK scalars
    U+4E00 through U+4E4F, which has 78 distinct trigrams. Assert:
    - the count is 64;
    - the first element is the first three scalars;
    - the last element is scalars 64-66 (1-based), which proves
      first-occurrence order;
    - `Set(trigrams).count == 64`.
- Keep every other assertion in the test unchanged (lines 7-10 and 12-14).
- Do not change `SearchQueryBuilder.trigrams`.

**P03-S2. Empty question returns `[]` before the limit check.**

- `StriaStore+Search.swift:fuzzyRetrieve` currently validates `limit` (1...100)
  before it checks for an empty question.
- An empty or whitespace-only question, or one with no tokens, must return
  `[]` regardless of `limit`.
- A non-empty question with an out-of-range limit still throws `usageError`.
- Tests (in `Tests/StriaCoreTests/Storage/FuzzyRetrieveTests.swift`):
  - `fuzzyRetrieve(question: "", documentId: nil, limit: 0)` returns `[]`.
  - `fuzzyRetrieve(question: "   ", documentId: nil, limit: 101)` returns
    `[]`.
  - `fuzzyRetrieve(question: "transformer", documentId: nil, limit: 0)`
    still throws `usageError`.
- Red evidence: the first two cases are the red cases. They fail before the
  fix because the limit check throws first. An empty question with a valid
  limit is already green today, so it cannot serve as red evidence. The
  third case guards the unchanged behaviour.

**P03-S3. Snippet matching must follow LIKE semantics.**

- `SearchQueryBuilder.swiftSnippet` uses `.diacriticInsensitive`. SQL `LIKE`
  is not diacritic-insensitive, so the snippet can bracket a different
  occurrence than the one that matched.
- Remove `.diacriticInsensitive` and keep `.caseInsensitive`.
- Do not change the 40-character window, the `...` markers or the `[` `]`
  bracketing.

**P03-S4. Make `SearchTests` prove what the plan claims.**

Add or strengthen these cases in `Tests/StriaCoreTests/Storage/SearchTests.swift`.
Do not delete or loosen any existing assertion.

- **English search:** assert both `docId` and `page` of the hit, not only
  the doc.
- **Cross-document:** two docs with 3 pages each, where a term appears only
  in doc2 page 2. The first result is exactly `(doc2, 2)` and there is
  exactly 1 result.
- **Doc filter:** a term present in both docs, searched with `documentId:
  doc1`. Results are non-empty and every result is doc1. Without the filter,
  both docs appear.
- **LIKE escaping (forced LIKE backend):**
  - page A stores `50xyoff`, page B stores `50%_off`;
  - searching `50%_off` returns only page B, which proves `%` and `_` are
    literals;
  - searching `5` (1 character, so LIKE mode) still matches.
- **NFKC both directions:** ASCII text `ABC 123` is found by the full-width
  query `ＡＢＣ`. Assert this on the default backend and on a store opened
  with `StoreOptions(forceLikeSearch: true)`. Keep the existing
  full-width-text test.
- **Snippet (P03-S3):** on a store opened with
  `StoreOptions(forceLikeSearch: true)`, so that the Swift snippet path
  runs, text `café then cafe` and query `cafe` give a snippet containing
  `[cafe]` and not `[café]`. Also add a unit assertion on
  `SearchQueryBuilder.swiftSnippet(text:term:)` directly.

**P03-S5. Make `FuzzyRetrieveTests` prove ranking and the fallback paths.**

Add these cases to `Tests/StriaCoreTests/Storage/FuzzyRetrieveTests.swift`:

- **Ranking:** a document with a page containing "transformer attention"
  and a distractor page containing only "attention". The question
  "transformer attention mechanism" ranks the first page first. This holds
  on both the fts5 backend (when available) and forced LIKE.
- **No trigram tokens:** the question `"AI 学習"` (all tokens shorter than 3
  scalars, so the `like` short-token path) uses three pages:
  - page 1 contains both `AI` and `学習` (for example "AI と 学習") and is
    returned;
  - page 2 contains `AI` but not `学習` and is not returned;
  - page 3 contains `学習` but not `AI` and is not returned.
  - This proves every short token is required (`like` mode, per
    `design-storage.md#fuzzy-retrieval-ask`). Pitfall: do not change
    `fuzzyShortLike` to OR the tokens.
- **Empty question:** covered by the P03-S2 cases (limit 0 and 101); do not
  add a separate green-only case.

### Accepted divergences (no change; reviewers must not reopen these)

- `SQLiteConnection.transaction` is `throws`, not `rethrows`.
- The connection opens with `SQLITE_OPEN_FULLMUTEX`.
- `Migrations.run` checks `user_version` before applying the pragmas. This
  is safer: a too-new DB stays unmodified (`design-storage.md#migrations`).
- `searchBackend` is a `let`.
- Mutating methods throw `documentNotFound` or `pageNotFound` when no row
  changes.
- `trigrams` stops collecting short tokens once it reaches the cap. Short
  tokens are only used when there are no trigrams.

### Review check (no new test)

The `pageInfo`, `pageInfos` and `listDocuments` SQL must not select the
`image` column. Verify with
`grep -n "SELECT" Sources/StriaCore/Storage/StriaStore+Pages.swift Sources/StriaCore/Storage/StriaStore+Documents.swift`
and record the output in the Progress Log.

### Test integrity

- The only existing assertion this plan may change is
  `SearchQueryBuilderTests.swift:11` (P03-S1).
- Every new behaviour-fix test (P03-S2, P03-S3) must be run once before the
  code fix, and the failing output kept in
  `tmp/stria-v01-session-245/P03/red-<task>.log`.

### Done criteria (mechanically checkable)

- `swift build --build-tests` exits 0 (`tmp/stria-v01-session-245/P03/build-tests.log`).
- `swift test --filter 'MigrationTests|DocumentStoreTests|PageStoreTests|SearchTests|SearchQueryBuilderTests|FuzzyRetrieveTests|ChatStoreTests'`
  exits 0 with 0 failures. Run it at the end of the run, after any wait
  (`tmp/stria-v01-session-245/P03/focused-final.log`).
- `swiftlint lint Sources/StriaCore/Storage Sources/StriaCore/Library/StriaLibrary.swift Tests/StriaCoreTests/Storage`
  reports 0 violations.
- `git diff 0082491 -- Tests/StriaCoreTests/Storage` removes no `#expect`
  or `#require` line, apart from the single P03-S1 replacement. Paste the
  diff stat into the Progress Log.

## Session-243 Notes (still valid)

The tasks, contracts and paths are unchanged from session 241. Checked
against the wave-1 code: the models this plan consumes exist with the
names used below:

- `Sources/StriaCore/Models/DocumentModels.swift:DocumentRecord`, `OCRCounts`;
- `Models/PageModels.swift:PageInfo`, `StoredPageImage`, `PageRef`;
- `Models/ChatModels.swift:ChatMessageRecord`, `NewChatThread`, `AskExchange`;
- `Models/RunModels.swift:AgentRunRecord`;
- `Models/SearchModels.swift:SearchHit`, `SearchOutcome`;
- `Models/DomainEnums.swift:SearchBackend`, `MatchMode`, `DocumentOrder`;
- `Models/StriaDateFormat.swift:StriaDateFormat`;
- `Errors/StriaError.swift` static constructors such as `.database(_:)`,
  `.databaseTooNew(_:)` and `.usage(_:)`.

Use these models as-is and never redefine them. Declared paths are
repository source paths only; no `.build/`, `tmp/` or nested-`.git` path is
declared.

## Intent and Context

`StriaStore` is the single source of truth for documents, page image
BLOBs, OCR text, FTS search, chats and agent runs. It uses the macOS system
`SQLite3` module (`import SQLite3`) with no third-party package. P07 (import
and OCR) and P08 (ask and search) call the exact API below in wave 3.

## Non-goals

- No image decoding or encoding: the store keeps BLOB bytes opaque.
- No PDF access, no file cache, and no JSONL logs (P05 writes the logs).
- No document deletion.
- No migrations beyond v1.

## writePaths

- `Sources/StriaCore/Storage`
- `Sources/StriaCore/Library/StriaLibrary.swift`
- `Tests/StriaCoreTests/Storage`
- `impl-plans/active/stria-03-storage.md`

## sharedPaths

- `Sources/StriaCore/Models`
- `Sources/StriaCore/Errors/StriaError.swift`
- `Sources/StriaCore/Paths/StriaPaths.swift`
- `Sources/StriaCore/Library/StriaEnvironment.swift`
- `Tests/StriaCoreTests/Support`
- `Package.swift`

## sharedPathNotes

- `{path: "Sources/StriaCore/Storage", intendedEdit: "directory"}`
- `{path: "Tests/StriaCoreTests/Storage", intendedEdit: "directory"}`
- `{path: "impl-plans/active/stria-03-storage.md", intendedEdit: "append to the Progress Log section only"}`
- `{path: "Sources/StriaCore/Models", intendedEdit: "read-only; models owned by P01"}`
- `{path: "Sources/StriaCore/Errors/StriaError.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Paths/StriaPaths.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Library/StriaEnvironment.swift", intendedEdit: "read-only"}`
- `{path: "Tests/StriaCoreTests/Support", intendedEdit: "read-only; test helpers owned by P01"}`
- `{path: "Package.swift", intendedEdit: "read-only"}`

## Files and Contracts

### `Storage/SQLiteConnection.swift`

- `final class SQLiteConnection` (internal; not `Sendable`; owned by the
  actor).
- `init(path:)` opens the DB with `sqlite3_open_v2` and
  `SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE`.
- `deinit` calls `sqlite3_close_v2`.
- `execute(_ sql:)`, `prepare(_:) -> Statement`, `transaction<T>(_ body:
  () throws -> T) rethrows -> T` (`BEGIN IMMEDIATE` / `COMMIT` /
  `ROLLBACK`), `savepoint`, `lastInsertRowID`, `changes`.
- `Statement`:
  - binds `Int`, `Int64`, `Double`, `String?` and `Data?`;
  - `step() -> Bool`;
  - column readers;
  - `reset`;
  - `finalize` in `deinit`.
- Text and blob binding must use `SQLITE_TRANSIENT`, written as
  `unsafeBitCast(-1, to: sqlite3_destructor_type.self)`.
- Errors map to `StriaError(code: .databaseError, message:
  sqlite3_errmsg)`.

### `Storage/Migrations.swift`

- Open sequence: run `PRAGMA journal_mode=WAL` (it returns a row, so step
  it), `PRAGMA busy_timeout=5000` and `PRAGMA foreign_keys=ON`.
- Read `PRAGMA user_version`:
  - greater than 1: throw `databaseTooNew` without modifying the DB;
  - 0: run migration 1 inside `BEGIN IMMEDIATE`, re-checking
    `user_version` inside the transaction so two processes do not both
    migrate.
- Migration 1 creates exactly the tables and indexes of
  `design-storage.md#schema-v1`: `meta`, `documents`, `pages`,
  `agent_runs`, `chat_threads`, `chat_messages` and the four indexes.
- FTS probe, inside `SAVEPOINT fts_probe`, unless `options.forceLikeSearch`
  is set:
  - run `CREATE VIRTUAL TABLE page_fts USING fts5(document_id UNINDEXED,
    page_number UNINDEXED, body, tokenize='trigram')`;
  - on success, insert `meta('search_backend','fts5')`;
  - on failure, `ROLLBACK TO fts_probe`, release the savepoint, and insert
    `'like'`.
- Finally set `PRAGMA user_version=1` and commit.

### `Storage/StriaStore.swift`

```
public struct StoreOptions: Sendable { public var forceLikeSearch: Bool = false }
public actor StriaStore {
  public init(databaseURL: URL, options: StoreOptions = .init(), clock: @escaping @Sendable () -> Date = { Date() }) throws
  public var searchBackend: SearchBackend { get }
}
```

### `Storage/StriaStore+Documents.swift`

All of these are `public` and `throws`:

- `insertDocument(_ record: DocumentRecord)`
- `document(id: String) -> DocumentRecord?`
- `document(sha256: String) -> DocumentRecord?`
- `markDocumentReady(id: String, outlineJSON: String?)`: sets
  `import_status = 'ready'` and `updated_at`.
- `listDocuments(order: DocumentOrder) -> [DocumentRecord]`:
  `importedDescending` orders by `imported_at DESC, id`; `recents` orders by
  `last_opened_at DESC NULLS LAST, imported_at DESC`. Emulate `NULLS LAST`
  with `last_opened_at IS NULL, last_opened_at DESC` for older SQLite.
- `ocrCounts(documentId: String) -> OCRCounts`
- `setLastReadPage(documentId: String, page: Int)`
- `markOpened(documentId: String)`: sets `last_opened_at` to now.

### `Storage/StriaStore+Pages.swift`

All `public throws`:

- `insertPage(documentId: String, pageNumber: Int, image: StoredPageImage)`:
  its own transaction, `ocr_status 'pending'`, `created_at` now.
- `pageNumbers(documentId: String) -> [Int]`: ascending; used to resume an
  interrupted render.
- `pageInfo(documentId: String, page: Int) -> PageInfo?`: never selects the
  `image` column.
- `pageInfos(documentId: String) -> [PageInfo]`: no blob.
- `pageImage(documentId: String, page: Int) -> StoredPageImage?`
- `pageNumbers(documentId: String, statuses: Set<OCRStatus>) -> [Int]`
- `recordOCRSuccess(documentId:page:text:vendor:model:run: AgentRunRecord)`.
  In one transaction:
  1. insert the `agent_runs` row;
  2. update the page: `ocr_status 'done'`, `ocr_text = text`,
     `search_text = NFKC(text)`, vendor, model, `ocr_error = NULL`,
     `ocr_updated_at`;
  3. if the backend is `fts5`, delete the page's `page_fts` row and insert
     `(document_id, page_number, search_text)`.
- `recordOCRFailure(documentId:page:error:vendor:model:run:)`. In one
  transaction:
  1. insert the run;
  2. update the page: `ocr_status 'failed'`, `ocr_error = error`,
     `ocr_attempts = ocr_attempts + 1`, `ocr_text = NULL`,
     `search_text = NULL`, vendor, model, `ocr_updated_at`;
  3. delete the `page_fts` row.
- NFKC idiom: `text.precomposedStringWithCompatibilityMapping`.

### `Storage/SearchQueryBuilder.swift` (pure, internal, unit-tested)

- `normalize(_:)`: NFKC, then trim.
- `terms(_:)`: split on whitespace.
- Mode decision: `fts` when the backend is `fts5` and every term has 3 or
  more Unicode scalars (`unicodeScalars.count >= 3`, because the trigram
  tokenizer counts code points); otherwise `like`.
- `ftsMatchExpression(terms:)`: each term wrapped in `"`, with internal `"`
  doubled, joined by ` AND `.
- `likePattern(term:)`: escape `\`, `%` and `_` with `\`, then wrap in `%`.
- `trigrams(question:)`:
  - tokens come from splitting on whitespace and punctuation
    (`CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)`);
  - each token of 3 or more scalars contributes its distinct sliding
    3-scalar windows, in order of first appearance, capped at 64 in total;
  - also return the short tokens, for the LIKE path.
- `swiftSnippet(text:term:)`: up to 40 characters on either side of the
  first case-insensitive match, with the match wrapped in `[` `]` and `...`
  added where text was cut.

### `Storage/StriaStore+Search.swift`

- `public func search(text: String, documentId: String?, limit: Int) throws
  -> SearchOutcome`:
  - an empty normalized query throws `usageError`;
  - a limit outside 1...100 throws `usageError`;
  - `fts` mode: `SELECT ... FROM page_fts JOIN documents ON
    documents.id = page_fts.document_id WHERE page_fts MATCH ? [AND
    page_fts.document_id = ?] ORDER BY bm25(page_fts) LIMIT ?`; snippet from
    `snippet(page_fts, 2, '[', ']', '...', 16)`; score is
    `-bm25` rounded to 6 decimals;
  - `like` mode: `pages.search_text LIKE ? ESCAPE '\'` for every term, AND
    the optional doc filter, ordered by `document_id, page_number`, score 0,
    with the snippet from `swiftSnippet` using the first term.
- `public func fuzzyRetrieve(question: String, documentId: String?, limit:
  Int) throws -> [PageRef]`:
  - `fts5` backend with trigrams: `MATCH` the trigram phrases joined by
    ` OR `, ordered by bm25;
  - `like` backend with trigrams: score is the sum of
    `(search_text LIKE ? ESCAPE '\')` over the trigrams, keeping score >= 1,
    ordered by score DESC, document_id, page_number;
  - no trigrams (all tokens shorter than 3): `like` mode with all short
    tokens, every token required;
  - an empty question returns `[]`.

### `Storage/StriaStore+Chat.swift`

All `public throws`:

- `persistAskExchange(_ exchange: AskExchange)`. In one transaction, in
  this order (foreign keys are enforced immediately):
  1. if `newThread` is non-nil, insert the `chat_threads` row; otherwise
     update the thread's `updated_at`;
  2. insert the `agent_runs` row;
  3. insert the user message (`status 'ok'`, content = question, the anchor
     doc and page, vendor and model null, `citations_json` null);
  4. insert the assistant message (status, content, the same anchor doc and
     page, vendor, model, `agent_run_id`, and `citations_json` as a JSON
     array of `{docId, page}`).
- `history(documentId: String?, page: Int?, limit: Int) -> [ChatMessageRecord]`:
  - a page without a doc throws `usageError`;
  - filtering follows `design-storage.md#chat-history-queries`;
  - select the newest `limit` rows by `created_at DESC, id DESC`, then return
    them reversed (oldest first).
- `threadMessages(threadId: String) -> [ChatMessageRecord]`: ordered by id.
- `agentRuns(documentId: String?) -> [AgentRunRecord]`: ordered by
  `started_at, id`; used by tests and the facade.

### `Library/StriaLibrary.swift`

```
public struct StriaLibrary: Sendable {
  public let environment: StriaEnvironment
  public let store: StriaStore
  public var paths: StriaPaths { get }
  public static func open(environment: StriaEnvironment, storeOptions: StoreOptions = .init()) throws -> StriaLibrary
}
```

`open` calls `paths.ensureDirectories()` and then opens the store at
`paths.database` with `environment.clock`. P07 and P08 add extensions in
their own files.

## Pitfalls

- Dates are stored as `StriaDateFormat` strings. Never store
  `Date.timeIntervalSince1970`.
- Never `SELECT *` from `pages` in list or info queries: it loads BLOBs.
- `page_fts` exists only when the backend is `fts5`. Guard every FTS
  statement on `searchBackend`.
- `persistAskExchange` must insert `agent_runs` before `chat_messages`, or
  foreign key checks fail.
- With FTS5, a quoted phrase shorter than 3 characters never matches. That
  is why the `like` mode exists, so do not "fix" it by lowering the
  threshold.

## Tests (`Tests/StriaCoreTests/Storage/`)

Use `withTestDataRoot`, and insert pages with arbitrary bytes, for example
`Data([1,2,3])` with format heic and 10x10.

`MigrationTests`:

- fresh DB -> `user_version` 1, all tables exist, `meta.search_backend` is `fts5` or `like`
- reopen -> no error, still v1
- `user_version` set to 2 manually -> `databaseTooNew`; the file hash is unchanged
- `forceLikeSearch` -> backend `like`, and no `page_fts` in `sqlite_master`

`DocumentStoreTests`:

- insert + fetch by id and sha -> equal records
- `markDocumentReady` -> status `ready`
- recents order -> an opened doc comes first
- `setLastReadPage` -> persisted

`PageStoreTests`:

- `pageInfo` does not need the blob, and `pageImage` returns the same bytes
- pending -> `recordOCRSuccess` -> done, text and `search_text` set, run row exists
- done -> `recordOCRFailure` -> failed, text nil, attempts 1, FTS row gone (search returns nothing)
- `pageNumbers(statuses:[.pending,.failed])` -> correct list

`SearchTests` (each runs on the default backend and again with `forceLikeSearch`):

- English 3+ char term -> the correct doc and page; `matchMode` is `fts` on the fts5 backend and `like` on the forced backend
- Japanese "機械学習" -> hit
- 2-char Japanese "学習" -> `matchMode` `like`, hit
- two docs, a term unique to doc2 page 2 -> exactly doc2 p2 first
- `--doc` filter -> excludes the other doc
- the literal query `50%_off` stored in text -> only the exact match; `%` and `_` are not wildcards
- empty query -> `usageError`
- limit 0 -> `usageError`
- full-width "ＡＢＣ" query matches "ABC" text (NFKC)

`SearchQueryBuilderTests`:

- quotes doubled
- trigram cap 64
- distinct and ordered output
- snippet brackets

`FuzzyRetrieveTests`:

- question "What does the transformer encoder do?" with one page containing "transformer encoder" -> that page ranked first, on both backends

`ChatStoreTests`:

- exchange with a new thread -> 2 messages + 1 run; both messages carry the anchor doc and page
- per-page history returns both; per-PDF history returns all of the doc's
- history `page` without doc -> `usageError`
- limit 1 -> returns the newest message only
- failed exchange (status error) is persisted
- `citations` round-trip

## Verification

- `swift build` -> exit 0 (`tmp/verify/P03/build.log`)
- `swift test --filter StriaCoreTests.MigrationTests` (and the other suites
  in this plan; or `swift test --filter Storage` if the suites are grouped)
  -> all pass (`tmp/verify/P03/test.log`)
- `swiftlint lint Sources/StriaCore/Storage Sources/StriaCore/Library/StriaLibrary.swift Tests/StriaCoreTests/Storage`
  -> exit 0 (`tmp/verify/P03/lint.log`)
- `wc -l` on the files above -> every file under 1000 lines

## Done Criteria

- [ ] All APIs above exist with the exact signatures.
- [ ] Both search backends are tested.
- [ ] The ask exchange persists in foreign-key-safe order.
- [ ] No BLOB is read by list or info queries.

## Progress Log

- (worker appends entries here)

- 2026-10-02 (P03 implementation): Added the SQLite connection, schema-v1 migration and backend probe, actor store and document/page/search/chat APIs, query builder, and `StriaLibrary` facade. Added all seven assigned storage test suites. Completion criteria: signatures and schema implemented; forced LIKE and FTS coverage authored; ask transaction inserts thread, run, user, assistant in FK-safe order; page info/document list projections omit `image`. Behavioral suite execution is pending because SwiftPM currently fails compiling another plan's `Tests/StriaCoreTests/Imaging/P04ImagingTests.swift:19` (`#expect` contains an unhandled throwing expression); see P03 evidence logs under `tmp/stria-v01-session-243/P03/`. `swift build`, selected-file strict SwiftLint, and the under-1000-line gate pass. Review/integration gates and commit remain downstream workflow steps.
- Final P03 verification retry: `swift build` exit 0 (`tmp/stria-v01-session-243/P03/build-source-final.log`); exact changed-file `swiftlint lint --strict --quiet --no-cache` exit 0 (`lint-source-final.log`); 1000-line gate exit 0 (`line-count-source-final.log`). The assigned `swift test --filter 'MigrationTests|DocumentStoreTests|PageStoreTests|SearchTests|SearchQueryBuilderTests|FuzzyRetrieveTests|ChatStoreTests'` stops during shared test-target compilation at P04's `Tests/StriaCoreTests/Imaging/P04ImagingTests.swift:19`; no P03 behavioral tests executed (`test-final-attempt.log`). P03 does not own that write path; serial integration must repair it and rerun this suite.

### Session 245

- (worker appends entries here; entries above are session-243 history)
- 2026-10-02 (session 245, Step 6): Completed P03-S1..S5. P03-S1 now expects the four actual distinct repeated trigrams and verifies exactly 64 distinct CJK trigrams in first-occurrence order. P03-S2 returns an empty result before limit validation, with tests for empty and whitespace input at limits 0 and 101 plus the non-empty invalid-limit guard. P03-S3 keeps case-insensitive snippet matching without diacritic folding. P03-S4 adds the missing doc/page, unique cross-document page, useful document filter, literal wildcard, both-direction NFKC on default/LIKE, and LIKE snippet assertions. P03-S5 verifies ranking against an attention-only distractor on FTS and LIKE and requires every short token.
  - Source identity before edits (SHA-256): `StriaStore+Search.swift` `46c229870fbded37e123fb5936e183a9edaa56551b0964e2bf798ac0c766ae38`; `SearchQueryBuilder.swift` `5c34d3a1f3e14c82a08b46be7aec6acfbc7a476e6925e88817b7eb1b8a649b8d`; `FuzzyRetrieveTests.swift` `706a7f5133c69d53b56047079ba2be59b515b575d003e22409f1deaa4540b083`; `SearchQueryBuilderTests.swift` `30932ef6b546ccba909ee87fd7e352b300326707d5c57bff13aeb9046f91a78f`; `SearchTests.swift` `1569be41904dd37a179d91661b9abd6819e1c20a8dc1a5c70a852c9ab04fce08`.
  - Current source SHA-256: `StriaStore+Search.swift` `d544f93785605a4154035c3aa48196f5e952c49c3b62acf5a2b9957da3cd2bb8`; `SearchQueryBuilder.swift` `d8d3ddde56ba741ca6c98d43f48811e576210f5c6a6999b3b48705f7341bc377`; `FuzzyRetrieveTests.swift` `c2a775b0708206c66979dfc1f9eea8fda121e7b76610b0edcfd762c1dadba5b3`; `SearchQueryBuilderTests.swift` `46491be8c67fb11cc066804a0364d8da42e6351cfc5c482906bbe4456bcf8abe`; `SearchTests.swift` `d8b9f8a6bfee4f4989c90fa6e2b37ce3ee88a5b8f9c48fe15000ba9889270d89`.
  - Red evidence: `tmp/stria-v01-session-245/P03/red-S2-S3.log` shows the empty-question limit failure and both diacritic-snippet failures before their production fixes. The original baseline focused output is `baseline-focused.log` (the known repeated-input cap assertion failed). Initial green compilation was interrupted because foreign `Sources/StriaCore/CLI/Usage.swift` changed during the build (`green-S2-S3-and-expanded.log`); after waiting 2 minutes, the retry exposed a fixture mismatch in the newly added ranking case, which was corrected to match the planned candidate text. `green-S5-ranking.log` then passed all 3 FuzzyRetrieveTests.
  - `swiftlint lint --strict --quiet --no-cache` on the NUL manifest of the five changed Swift files: exit 0 (`swiftlint-changed-strict.log`). Plan's broader SwiftLint command: 0 violations in 159 files, exit 0 (`swiftlint-plan.log`). The under-1000-line gate passes (`line-count.log`). SQL projection grep confirms `pageInfo`, `pageInfos`, and `listDocuments` omit the image BLOB; only `pageImage` selects it (`sql.log`). Test-integrity check passes; diff has only the authorized removed S1 assertion (`test-integrity.log`; diff stat: 3 files changed, 113 insertions, 2 deletions).
  - `swift build --build-tests` passes at this source tree (`build-tests.log`). Final focused command is `swift test --filter 'MigrationTests|DocumentStoreTests|PageStoreTests|SearchTests|SearchQueryBuilderTests|FuzzyRetrieveTests|ChatStoreTests'`; its final-source evidence is `focused-final.log`.
  - P03 completion criteria for this stabilization run are satisfied by the code and test coverage above; final focused test result is recorded in the Step 6 output. Formal test-integrity/adversarial review, serial join, plan acceptance/move, and commit remain downstream workflow steps.
- 2026-10-02 (session 245, Step 8 serial finalization): accepted by the test-integrity and adversarial gates and the post-join integration review (comm-003268). Combined-tree evidence in `tmp/stria-v01-session-245/join/wave-5/`: `swift build --build-tests` exit 0 (`build-tests.log`), `swift test` 120 tests in 36 suites exit 0 (`swift-test-full.log`), `scripts/cli-smoke.sh` SMOKE OK exit 0 (`cli-smoke.log`). Moved to `impl-plans/completed/`. The Done Criteria checkboxes are kept as authored (intent snapshot); this entry records that they are met.
