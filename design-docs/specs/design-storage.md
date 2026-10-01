# Storage, Import Pipeline, Cache and Search

## Status

Draft (stria v0.1).

## Data Root Layout

| Path | Owner | Notes |
| --- | --- | --- |
| `<root>/stria.sqlite` (+ `-wal`, `-shm`) | `StriaStore` | Single source of truth for documents, page images, OCR text, chats and agent runs |
| `<root>/originals/<docId>.pdf` | importer | Byte-identical copy of the imported file. The app displays this file |
| `<root>/cache/<docId>/page-NNNN.png` | `PageImageCache` | Expanded page images for models. Never displayed. Safe to delete at any time |
| `<root>/config.json` | `ConfigStore` | See `design-agent-integration.md#config` |
| `<root>/logs/agent-runs-YYYY-MM-DD.jsonl` | run recorder | See `design-agent-integration.md#run-records` |

`NNNN` is the 1-based page number formatted with `%04d`. Pages above 9999
naturally get more digits. `original_path` is stored relative to the root
(`originals/<docId>.pdf`), so a moved root keeps working. JSON output always
prints absolute paths. Every file write goes to a temp file in the destination
directory and is then atomically renamed.

## Document Identity

- `sha256`: lowercase hex SHA-256 of the original file bytes (CryptoKit).
- `docId`: the first 16 hex characters of `sha256`.
- Importing a file whose `sha256` already exists returns the existing
  document with `alreadyImported: true`. It does not copy, re-render or
  re-OCR. If that document is still `rendering` from an interrupted import,
  rendering resumes from the first missing page.
- If a `docId` exists with a different `sha256`, the import fails with
  `idCollision`. This is not expected in practice, and the id is never
  lengthened automatically.
- `title`: the trimmed PDF `Title` attribute if it is non-empty, otherwise
  the file name without its extension.

## Import Pipeline

1. Open the file with `PDFDocument(url:)`. Reject unreadable files, locked
   files (encrypted with a user password, `isLocked`), and zero-page files
   with `invalidPDF`. A PDF that is encrypted only with an owner password
   (permission restrictions) opens without a password and is accepted.
2. Hash the file and run the idempotency check above.
3. Copy it to `originals/<docId>.pdf` (atomic).
4. Insert the `documents` row with `import_status = 'rendering'`, the render
   settings, and the OCR vendor and model from the current config.
5. For each page, sequentially, inside an autorelease pool:
   - render the crop box with the page rotation applied, on a white
     background, sRGB, 8-bit RGB without alpha, at `render.dpi` (default
     150). Reduce the scale so the longest side never exceeds
     `render.maxPixelDimension` (default 4096), which bounds memory for
     oversized pages;
   - encode with the image codec (below) and insert the `pages` row with
     `ocr_status = 'pending'` in its own transaction, so an interrupted import
     resumes from the first missing page.
6. Extract the outline: convert `PDFOutline` to a tree of
   `{title, page, children}`, where `page` is 1-based, or null when the
   destination is missing. Store it as `outline_json` and set
   `import_status = 'ready'`.
7. Unless `--no-ocr` is set, hand the document to the OCR coordinator. OCR
   errors and unavailability never fail the import
   (`design-agent-integration.md#ocr`).

Progress is reported as an `AsyncStream<ImportEvent>` with the events
`copied(docId)`, `rendered(page, total)`, `ocr(done, failed, pending, total)`,
`finished(docId)` and `failed(error)`.

## Image Codec

Decision: HEIC (`public.heic`) at `render.quality` 0.75 by default, written
through ImageIO `CGImageDestination`. JPEG (`public.jpeg`) at the same quality
is the automatic fallback when HEIC encoding is unavailable, meaning
destination creation or finalize fails (as it can on some virtualized hosts).
`render.imageFormat` may also be set to `jpeg` explicitly. The format is
stored per page, so decoding never depends on the current config.

Rationale: the stored image is an archival source for later PNG expansion and
model input, not for display. For text pages, HEIC is roughly half the size of
JPEG at the same visual quality, which serves the explicit "save disk"
requirement. Lossless PNG would be several times larger. At 150 DPI and 0.75
quality, glyph edges stay clean enough for OCR models. Expansion always
produces PNG because model vendors do not accept HEIC. At about 100-250 KB per
HEIC page, a 500-page PDF adds roughly 50-125 MB to the DB.

## Expanded PNG Cache

- `expand(docId, page)` decodes the BLOB, writes `cache/<docId>/page-NNNN.png`
  and returns the absolute path.
- A cache file is valid when it exists, is non-empty, and ImageIO reports the
  same pixel width and height as the `pages` row. Valid files are not
  rewritten. Invalid files are rewritten atomically.
- Triggers:
  - app document open: all pages, in the background, concurrency 2, cancelled
    when another document is opened;
  - `stria page image`: one page;
  - OCR: each page before it is sent;
  - ask: the selected context pages.
- `stria page image --output <path>` writes the PNG to `<path>` only and does
  not touch the cache.

## SQLite

Decision: the system `SQLite3` module (`import SQLite3`) with a thin wrapper
(prepared statements, blobs, transactions). No third-party SQLite package.

Connection settings: WAL journal, `busy_timeout = 5000`, `foreign_keys = ON`,
and one connection per process owned by the `StriaStore` actor. Page BLOBs are
read one page at a time. No query loads all the images of a document.

### Migrations

Migrations are versioned with `PRAGMA user_version`. Each migration runs in
one transaction and bumps `user_version`. Opening a DB whose version is newer
than the binary knows fails with `databaseTooNew` and leaves the DB
unmodified. Re-opening an up-to-date DB runs nothing. v0.1 ships migration 1
only. Later schema changes add new numbered migrations and never edit
migration 1.

### Search Backend

Migration 1 decides the search backend once:

- It runs `CREATE VIRTUAL TABLE page_fts USING fts5(..., tokenize='trigram')`
  inside the migration transaction.
- If that succeeds, the migration stores `meta(key='search_backend',
  value='fts5')`.
- If it fails (FTS5 or trigram unavailable), the migration stores `'like'`
  and creates no FTS table. The migration still succeeds.
- `StriaStore` reads `search_backend` on open. A store option
  `forceLikeSearch` (used by tests only) creates `'like'` regardless, so the
  LIKE backend is tested on every host.

### Schema v1

```
meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)

documents(
  id TEXT PRIMARY KEY,               -- 16-hex docId
  sha256 TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  original_filename TEXT NOT NULL,
  original_path TEXT NOT NULL,       -- relative to data root
  byte_size INTEGER NOT NULL,
  page_count INTEGER NOT NULL,
  import_status TEXT NOT NULL CHECK (import_status IN ('rendering','ready')),
  render_dpi INTEGER NOT NULL,
  image_format TEXT NOT NULL,        -- requested format at import
  ocr_vendor TEXT, ocr_model TEXT,   -- OCR config at import time
  outline_json TEXT,                 -- null until rendered
  last_read_page INTEGER,            -- app reading position (1-based)
  last_opened_at TEXT,               -- app library recents ordering
  imported_at TEXT NOT NULL, updated_at TEXT NOT NULL)   -- ISO-8601 UTC

pages(
  document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  page_number INTEGER NOT NULL CHECK (page_number >= 1),
  image BLOB NOT NULL,
  image_format TEXT NOT NULL CHECK (image_format IN ('heic','jpeg')),
  width INTEGER NOT NULL, height INTEGER NOT NULL,
  ocr_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (ocr_status IN ('pending','done','failed')),
  ocr_text TEXT,                     -- as returned (post-processed)
  search_text TEXT,                  -- NFKC-normalized ocr_text; null unless done
  ocr_vendor TEXT, ocr_model TEXT, ocr_error TEXT,
  ocr_attempts INTEGER NOT NULL DEFAULT 0,
  ocr_updated_at TEXT,
  created_at TEXT NOT NULL,
  PRIMARY KEY (document_id, page_number))

page_fts USING fts5(                 -- only when search_backend = 'fts5'
  document_id UNINDEXED, page_number UNINDEXED, body,
  tokenize = 'trigram')              -- body = pages.search_text

agent_runs(
  id TEXT PRIMARY KEY,               -- UUID generated by stria before the call
  kind TEXT NOT NULL CHECK (kind IN ('ocr','ask')),
  document_id TEXT REFERENCES documents(id) ON DELETE SET NULL,
  page_number INTEGER,               -- OCR page, or ask anchor page
  vendor TEXT NOT NULL, model TEXT,
  status TEXT NOT NULL CHECK (status IN ('ok','failed')),
  error TEXT,                        -- redacted, max 2000 chars
  image_count INTEGER NOT NULL,
  started_at TEXT NOT NULL, finished_at TEXT NOT NULL,
  duration_ms INTEGER NOT NULL)

chat_threads(
  id TEXT PRIMARY KEY,               -- UUID
  document_id TEXT REFERENCES documents(id) ON DELETE CASCADE, -- null: library-wide ask
  page_number INTEGER,               -- anchor page at the first question
  scope TEXT NOT NULL CHECK (scope IN ('page','nearby','document','library')),
  created_at TEXT NOT NULL, updated_at TEXT NOT NULL)

chat_messages(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  thread_id TEXT NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user','assistant')),
  status TEXT NOT NULL DEFAULT 'ok' CHECK (status IN ('ok','error')),
  content TEXT NOT NULL,             -- assistant error rows hold the redacted error text
  document_id TEXT, page_number INTEGER,   -- page the question was about
  vendor TEXT, model TEXT,
  agent_run_id TEXT REFERENCES agent_runs(id) ON DELETE SET NULL,
  citations_json TEXT,               -- [{docId,page}] context pages sent
  created_at TEXT NOT NULL)

INDEX chat_messages_doc_page ON chat_messages(document_id, page_number, created_at)
INDEX chat_messages_thread ON chat_messages(thread_id, id)
INDEX pages_ocr_status ON pages(document_id, ocr_status)
INDEX agent_runs_doc ON agent_runs(document_id, started_at)
```

v0.1 has no document deletion, so `ON DELETE` actions only define behaviour
for later versions.

`page_fts` is a standalone FTS table, not an external-content table, so no
triggers are needed. `StriaStore` maintains it in the same transaction as
every `ocr_text` change: it deletes the page's row, and when the status
becomes `done` it inserts the new `search_text`.

OCR "in progress" is never persisted. A page being processed stays `pending`
(or `failed`) until its result is written, so a crashed run leaves nothing
stale to reset. Two concurrent runs on the same page are harmless: the last
write wins.

## Search

Search is shared by `stria search`, ask retrieval and the app's search mode.

- Normalization: the query and `search_text` are NFKC-normalized, which folds
  full-width and half-width forms. Trigram matching is case-insensitive, and
  LIKE is ASCII case-insensitive.
- Terms: the trimmed query is split on whitespace.
- `fts` mode (backend `fts5` and every term has 3 or more characters):
  - match: `page_fts MATCH` with each term as a quoted phrase (internal `"`
    doubled), joined by `AND`;
  - order: `bm25(page_fts)`, and `score = -bm25` rounded to 6 decimals;
  - snippet: `snippet(page_fts, 2, '[', ']', '...', 16)`.
- `like` mode (backend `like`, or any term shorter than 3 characters, such as
  a two-character Japanese word):
  - match: every term must match `pages.search_text LIKE '%term%' ESCAPE '\'`,
    with `%`, `_` and `\` escaped;
  - order: `document_id, page_number`, and `score = 0`;
  - snippet: computed in Swift as up to 40 characters on either side of the
    first match, with the term wrapped in `[` `]`.
- An empty query is a `usageError`. Options: a `docId` filter, and `limit`
  (default 10, range 1...100). Results join `documents` for `title`. The
  result reports the `matchMode` it used.

### Fuzzy retrieval (ask)

Natural-language questions rarely appear verbatim, so ask uses a separate
retrieval query built from the question:

- Split the NFKC-normalized question into tokens on whitespace and
  punctuation.
- Every token of 3 or more characters contributes its character trigrams
  (Unicode scalars) in first-occurrence order. Trigrams are de-duplicated
  across the whole question first, and the distinct list is then capped at
  64. Repeating a token adds nothing: `"transformer transformer encoder"`
  starts with `tra` and has no duplicates, `"abcdef"` repeated 20 times yields
  exactly 4 trigrams (`abc`, `bcd`, `cde`, `def`), and the cap of 64 is reached
  only by questions with more than 64 distinct trigrams. Tests assert the cap
  with such a question and do not loosen the dedup rule.
- Backend `fts5`: the trigrams are quoted phrases joined by `OR`, ranked by
  `bm25`.
- Backend `like`: a page matches when it contains at least one trigram. Its
  score is the number of distinct trigrams it contains (one `LIKE` expression
  per trigram summed in SQL), ordered by score descending, then
  `document_id, page_number`.
- If no token has 3 or more characters, `like` mode is used with the tokens.

## Chat History Queries

- Per page: `chat_messages WHERE document_id = ? AND page_number = ?`.
- Per PDF: `WHERE document_id = ?`.
- All: no filter. This includes library-wide asks with a null `document_id`.
- Results are ordered by `created_at, id`. `limit` defaults to the newest 50,
  returned oldest first. `--page` without `--doc` is a `usageError`.
