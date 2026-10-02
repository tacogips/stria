# Command

## Status

Implemented (stria v0.1). Replaces the scaffold CLI usage.

## Purpose

`stria` is primarily a tool for AI agents. Every command prints exactly one
JSON object on success and uses stable exit codes. Humans use the app.

## Global Rules

- Invocation: `stria [--home <path>] <command> [args] [options]`. `--home`
  may appear before or after the command name.
- JSON is the default and only output format. `--json` is accepted on every
  command and has no effect.
- `stria --help` and `stria <command> --help` print plain-text usage on
  stdout with exit 0. `stria --version` prints `Version.current`. None of
  these touch the data root.
- Success output: one JSON object plus a newline on stdout, exit 0.
  - Keys are camelCase and sorted (`JSONEncoder` `.sortedKeys`,
    `.withoutEscapingSlashes`).
  - Dates are ISO-8601 UTC strings, and paths are absolute.
  - Absent optional values are `null`, never omitted.
- Failure output: stdout stays empty; stderr gets
  `{"error":{"code":"<code>","message":"<text>"}}`; the exit code is
  non-zero.
- Any command that needs the DB, directories or default config creates them
  lazily. That is every command except `--help` and `--version`.

| Exit | Meaning | Error codes |
| --- | --- | --- |
| 0 | success | - |
| 1 | internal, IO or database error | `ioError`, `databaseError`, `databaseTooNew`, `idCollision`, `configInvalid` |
| 2 | usage error or invalid input | `usageError`, `invalidPDF` |
| 3 | not found | `documentNotFound`, `pageNotFound`, `noRelevantPages` |
| 4 | OCR or agent unavailable (config, credential env var, integration) | `serviceUnavailable` |
| 5 | OCR or agent call failed | `serviceFailed` |

`StriaCommand.run(arguments:environment:homeDirectory:services:) async ->
CommandOutput {stdout, stderr, exitCode}` lives in `StriaCore/CLI`.
`StriaCLI/main.swift` passes the real environment, the home directory and the
live services, then writes the output and exits. Tests call `run` directly
with a temp `--home` and fake services.

## Shared JSON Shapes

`DocumentSummary`:
`{id, title, pageCount, importStatus, importedAt, originalPath,
ocr: {done, failed, pending}}`

`OutlineNode`: `{title, page, children: [OutlineNode]}`. `page` is 1-based,
or null.

## Commands

### `stria import <pdf> [--no-ocr]`

Imports the PDF. Import is idempotent by content. Without `--no-ocr`, the
command OCRs `pending` pages before returning.

```json
{"alreadyImported": false, "document": DocumentSummary,
 "ocr": {"status": "completed|partial|skipped|unavailable",
         "reason": null, "done": 0, "failed": 0, "pending": 3}}
```

`ocr.status` values:

- `skipped`: `--no-ocr` was given, or the document was already imported;
- `unavailable`: the OCR service is unavailable. The import still succeeds
  with exit 0, and `reason` is set;
- `partial`: some pages failed.

### `stria ocr <docId> [--pages <list>] [--retry-failed]`

`<list>` is a comma-separated list of pages and inclusive ranges (`1,3-5`),
validated against the page count. The selection rules are in
`design-agent-integration.md#ocr`. The command exits 0 when the run completed,
even if some pages failed, and exits 4 when the service is unavailable.

```json
{"docId": "...", "processed": [1, 2], "done": 2, "failed": 0, "pending": 1,
 "failures": [{"page": 3, "error": "..."}]}
```

### `stria list`

`{"documents": [DocumentSummary]}`, ordered by `importedAt` descending.

### `stria show <docId>`

`{"document": DocumentSummary + {sha256, byteSize, renderDpi, imageFormat,
ocrVendor, ocrModel}, "outline": [OutlineNode]}`

### `stria remove <docId>`

Deletes the document row (pages, OCR text, FTS rows, chat threads and
messages cascade; `agent_runs` rows keep their data with `document_id`
set to null), then removes `originals/<docId>.pdf` and `cache/<docId>/`.
The file that was originally imported is not touched. The DB row goes first,
so an interrupted removal leaves orphan files, never rows that point at
missing files.

```json
{"docId": "...", "removed": true}
```

Unknown ids exit 3 (`documentNotFound`).

### `stria page image <docId> <page> [--output <path>]`

Expands the stored image to PNG, either into the cache or only to the
`--output` path.

```json
{"docId": "...", "page": 1, "path": "/abs/.../page-0001.png",
 "width": 1275, "height": 1650, "format": "png", "cached": true}
```

`cached` is true when the cache file was already valid. It is false when the
file was written now or when `--output` is used.

### `stria page text <docId> <page>`

`{"docId", "page", "ocrStatus", "text", "ocrError", "ocrVendor", "ocrModel"}`.
`text` is null unless `ocrStatus` is `done`.

### `stria search <query> [--doc <docId>] [--limit <n>]`

```json
{"query": "...", "matchMode": "fts|like",
 "results": [{"docId": "...", "title": "...", "page": 3, "snippet": "...[term]...",
              "score": 1.234, "imagePath": "/abs/.../page-0003.png", "imageCached": false}]}
```

`imagePath` is where `stria page image` puts the PNG, and `imageCached` says
whether that file already exists. In `like` mode `score` is the number of
times the terms occur on the page. Search semantics are in
`design-storage.md#search`.

### `stria ask <question> [--doc <docId>] [--page <n>] [--query <terms>] [--limit <n>]`

Returns the built-in RAG answer (`design-agent-integration.md#ask`).
`--page` requires `--doc`. `--limit` caps the number of context pages
(default `agent.maxImages`).

```json
{"threadId": "...", "answer": "...", "vendor": "...", "model": "...",
 "runId": "...",
 "citations": [{"docId": "...", "title": "...", "page": 3, "imagePath": "..."}]}
```

If the agent call fails, the exchange is still persisted and the command
exits 5.

### `stria history [--doc <docId>] [--page <n>] [--limit <n>]`

```json
{"messages": [{"id": 1, "threadId": "...", "role": "user|assistant",
  "status": "ok|error", "content": "...", "docId": null, "page": null,
  "vendor": null, "model": null, "runId": null, "citations": [], "createdAt": "..."}]}
```

### `stria config get [<key>]` / `stria config set <key> <value>`

- `get` without a key prints the whole config object. With a key it prints
  `{"key": "...", "value": ...}`.
- `set` validates the value (rules in `design-agent-integration.md#config`),
  writes the file atomically, and prints `{"key", "value"}`.
- Unknown keys and invalid values fail with `usageError` (exit 2) and leave
  the file unchanged.
- `stria config` alone is the same as `stria config get`.

### `stria paths`

```json
{"home": "...", "database": "...", "originals": "...", "cache": "...",
 "config": "...", "logs": "..."}
```

## Agent Usage

The CLI is a retrieval tool for an external agent:

1. Run `stria search "<key phrase>"` across all PDFs (add `--doc` to narrow
   it). Prefer distinctive phrases of 3 or more characters, because shorter
   terms use the slower `like` mode.
2. For the best hits, run `stria page image <docId> <page>` and read the PNG
   at `path`. Optionally run `stria page text` for the OCR text.
3. Answer the user and cite `docId` and page. Use `stria show <docId>` for
   the outline when neighbouring sections matter.

Alternatively, `stria ask "<question>"` performs retrieval and answering with
the configured agent and persists the exchange. The README carries a short
version of this section.

## CLI Smoke

`scripts/cli-smoke.sh` (mise task `smoke`) runs from the repo root:

1. Set `STRIA_HOME=$(mktemp -d)`. Generate two multi-page PDFs into that temp
   dir with `swift scripts/make-sample-pdf.swift <out> <variant>`
   (CoreGraphics and CoreText; distinct English and Japanese text per page).
2. Run `stria import <pdf> --no-ocr` for both. `stria list` shows 2
   documents.
3. `stria page image <docId> 1` returns a `path` that exists.
4. Run `stria config set ocr.vendor pdf-text-layer`, then `stria ocr <docId>`
   for both documents.
5. `stria search` for a phrase unique to document 2, page 2 returns that doc
   and page as the top result. A 2-character Japanese term returns
   `matchMode: like`.
6. `stria history` exits 0 with a `messages` array. The array is empty
   because the real binary has no offline agent.
7. Remove the temp dir.

Every step checks the exit code and parses the JSON with `/usr/bin/plutil`,
failing fast. The script never touches `~/.local/stria`.

`CLIEndToEndTests` in `StriaCoreTests` runs the same flow in-process through
`StriaCommand.run`, with a temp `--home`, `FakeOCRService` and
`FakeAgentService`. That flow also covers `ask` followed by `history`
returning the persisted exchange. This test is the "OCR via fake, persisted
chats" part of the acceptance smoke.
