# P03 SQLite Store, Migrations, Search, Chat and Agent Runs

**Status**: Ready
**planId**: P03
**Wave**: 2
**dependsOn**: P01
**Design Reference**: `design-docs/specs/design-storage.md` (all sections); `design-docs/specs/design-agent-integration.md#ocr` (state machine), `#persistence`

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
