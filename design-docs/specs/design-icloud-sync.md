# iCloud Sync

## Status

Implemented (StriaCore engine, configuration, controller, macOS settings, CLI,
and regression tests). The iOS folder picker and bookmark storage UI are part
of the mobile app task. `SyncFolder.Provider` resolves a bookmark each pass
and returns a `Location(url:securityScoped:)`; the engine brackets a pass with
security-scoped access.

Implementation decisions: explicit engine/CLI passes run even when automatic
sync is disabled; `sync.enabled` controls app scheduling and deletion propagation.
Deletion intents persist in SQLite `meta` atomically with local deletion, then
publish immediately when possible or retry during the next pass. Tombstone
transfers count as document transfers in reports. Timestamp ties keep the
existing side, using the store's existing second-resolution UTC format.
Filesystem coordination and timing have injectable boundaries for deterministic
tests. Production uses `NSFileCoordinator`; native iCloud service behavior
requires verification outside a restricted test sandbox. No other protocol
deviations; iOS-only UI is intentionally deferred.

## Goal

Optionally sync a library between the user's Macs, iPads and iPhones through
iCloud Drive. Settings decides whether syncing is on and which kinds of data
are synced: imported PDFs, OCR results (text and tags), page summaries, and
chat history. Configuration (vendors, models, prompts, keys) is per device
and never synced, because the usable vendors differ by platform.

## Where the data lives

A sync folder holds plain files that iCloud Drive replicates:

- macOS: `~/Library/Mobile Documents/com~apple~CloudDocs/Stria` (the
  "Stria" folder at the top of iCloud Drive). The app is not sandboxed, so it
  can use this path without an iCloud entitlement; iCloud Drive must be on.
  Settings can choose another folder instead (a folder picker).
- iOS / iPadOS: the user picks the same "Stria" folder in iCloud Drive with
  the system folder picker (`fileImporter`, `.folder`). The app stores a
  security-scoped bookmark and resolves it at each sync. No iCloud
  entitlement is needed for this. If an iCloud ubiquity container is available
  (`FileManager.url(forUbiquityContainerIdentifier: nil)` returns a URL, only
  with the entitlement), Settings may offer it as an alternative, but the
  picked folder is the default path that works with every build.
- `STRIA_SYNC_DIR` (environment) overrides the folder for tests and
  development.

Without a usable folder, sync reports "iCloud Drive is not available" and
does nothing.

## Config (`sync`, per device)

| Key | Default | Meaning |
| --- | --- | --- |
| `sync.enabled` | `false` | master switch |
| `sync.documents` | `true` | imported PDFs (originals and document metadata) |
| `sync.ocr` | `true` | OCR text and tags per page |
| `sync.summaries` | `true` | page summaries |
| `sync.chats` | `true` | chat threads and messages |
| `sync.folder` | `null` | macOS only: a folder path overriding the default; null = default |
| `sync.intervalMinutes` | `5` | periodic sync while the app is active (1...120) |

OCR, summaries and chats of a document are only synced when `sync.documents`
is on (they belong to documents). Library-wide chats (no document) follow
`sync.chats` alone. The iOS folder bookmark is stored outside `config.json`
(UserDefaults key `syncFolderBookmark`), because a bookmark is device data.

## Folder layout (format version 1)

```
Stria/
  format.json                          {"version": 1}
  documents/<docId>/document.json      document metadata (below)
  documents/<docId>/original.pdf       the imported file
  documents/<docId>/ocr/<page>.json    one page's OCR result
  documents/<docId>/summaries/<page>.json  one page's summary
  documents/<docId>/deleted.json       tombstone {"deletedAt": ...}
  chats/<threadId>.json                one thread with all its messages
  chats/<threadId>.deleted.json        tombstone (reserved; threads are not deletable yet)
```

All JSON is UTF-8, sorted keys, ISO-8601 UTC dates (`StriaDateFormat`).
One file per page and per thread keeps concurrent edits on different devices
from touching the same file.

- `document.json`: `docId`, `sha256`, `title`, `originalFilename`,
  `byteSize`, `pageCount`, `importedAt`, `updatedAt` (latest local change to
  the metadata), `outline` (optional).
- `ocr/<page>.json`: `page`, `status` (`done` | `failed`), `text`, `tags`,
  `error`, `vendor`, `model`, `updatedAt` (the page's `ocr_updated_at`).
  Pending pages are not written.
- `summaries/<page>.json`: the `PageSummaryRecord` fields plus
  `sourceOCRUpdatedAt` and `updatedAt`.
- `chats/<threadId>.json`: thread fields (`id`, `documentId`, `pageNumber`,
  `scope`, `title`, `summary`, `summaryThroughIndex`, `createdAt`,
  `updatedAt`) and `messages`: an array of `{role, status, content,
  documentId, page, vendor, model, citations, createdAt}` in order. Local
  message row ids are not synced; `summaryThroughIndex` is the index of the
  last message the summary covers.

Page images, the expanded PNG cache, agent run records and logs are never
synced; a device renders page images from the PDF itself.

## Algorithm

`SyncEngine` (StriaCore) runs one pass: `sync(folder:options:) async throws
-> SyncReport`. It works on any folder URL, so tests use temporary folders
and two data roots to stand in for two devices.

1. Prepare: create `format.json` if missing; refuse a folder whose format
   version is newer than known (report an error, change nothing).
2. Documents (when enabled):
   - Push: for each local ready document without a remote `document.json`,
     copy `original.pdf` (atomic: write to a temporary name in the same
     folder, then rename) and write `document.json`. Update `document.json`
     when the local metadata is newer.
   - Pull: for each remote document unknown locally and without a tombstone,
     import `original.pdf` through the normal import pipeline (`runOCR:
     false`; the doc id is the same everywhere because it derives from the
     PDF's SHA-256), then apply its OCR and summary files.
   - Deletion: removing a document locally (with sync on) writes
     `deleted.json` and removes the remote `original.pdf`, `ocr/` and
     `summaries/`. Pulling a tombstone removes the local document when it was
     not imported after `deletedAt`.
3. OCR (when enabled): per page, last writer wins by `updatedAt`. Push when
   the local `ocr_updated_at` is newer than the remote file (or there is no
   file); pull when the remote is newer. Pulled results are stored with the
   remote `updatedAt` as `ocr_updated_at` (a store method that does not stamp
   "now"), so the next pass sees them as equal and does not bounce them back.
   Pulled OCR text is indexed for search like local OCR.
4. Summaries (when enabled): the same per-page rule, by `updatedAt`, keeping
   `source_ocr_updated_at`, so staleness survives syncing.
5. Chats (when enabled): per thread, last writer wins by `updatedAt`. A
   pulled thread replaces the local thread's messages (and title/summary).
   Two devices adding messages to the same thread between syncs keep only
   the newer side; this is accepted and documented.
6. iCloud placeholders: a file not yet downloaded appears as
   `.<name>.icloud`. The engine calls
   `FileManager.startDownloadingUbiquitousItem(at:)` for it, skips it in this
   pass, and counts it as pending; a later pass picks it up. Reads and writes
   go through `NSFileCoordinator`.
7. Report: counts of pushed and pulled documents, OCR pages, summaries and
   threads, pending downloads, and per-item errors (one bad file never stops
   the pass).

## When it runs (apps)

`SyncController` (StriaCore app model, `@MainActor @Observable`) owns the
state shown in Settings: `isSyncing`, `lastSync` (date and report),
`lastError`, `folderDescription`. It syncs:

- at launch and when the app becomes active,
- every `sync.intervalMinutes` while active,
- a few seconds (debounced) after local changes: import, OCR, summary, chat
  answer, document removal,
- on "Sync Now".

Only one pass runs at a time; a request during a pass schedules one more.

## Settings

Section "iCloud Sync" (macOS and iOS):

- Toggle "Sync with iCloud Drive".
- Toggles: "PDFs", "OCR text and tags", "Page summaries", "Chat history"
  (disabled while sync is off; OCR and summaries also disabled while PDFs
  are off).
- The folder: macOS shows the path with "Choose Folder..." and "Use Default";
  iOS shows the picked folder name with "Choose iCloud Drive Folder..." (the
  user should pick or create `iCloud Drive/Stria`).
- Status: "Last synced 2 min ago: 3 PDFs, 40 pages, 12 summaries, 5 chats",
  pending downloads, the last error, and "Sync Now".

The library shows a small sync status (spinner while syncing, a warning icon
with the last error).

## CLI

`stria sync [--folder <path>]` runs one pass with the data root's `sync.*`
settings (the folder defaults to `STRIA_SYNC_DIR`, then `sync.folder`, then
the macOS default) and prints the report as JSON. `stria config` gains the
`sync.*` keys.

## Tests

Two data roots and one shared temporary folder: import on A, sync A, sync B
→ B has the document (rendered pages), searchable OCR body text and stored tags, and
summaries; OCR redone on B wins on A after both sync; chats flow both ways;
deletion tombstones propagate; disabled kinds are neither pushed nor pulled;
a newer `format.json` is refused; `.icloud` placeholders are skipped and
reported pending.
