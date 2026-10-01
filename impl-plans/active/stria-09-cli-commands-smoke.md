# P09 CLI Command Execution, Executable, End-to-End Tests, Smoke Script

**Status**: Ready (re-issued in session 243)
**planId**: P09
**Wave**: 3 of the session-243 manifest
**dependsOn**: P05, P06, P07, P08
**Design Reference**: `design-docs/specs/command.md` (all sections); `design-docs/specs/architecture.md#data-root`, `#implementation-rollout`; `design-docs/specs/design-agent-integration.md#run-records`, `#secrets`

## Session-243 Revision

The tasks, contracts and paths are unchanged from session 241. Two things
changed:

- The dependency on P02 is dropped: P02 is completed (commit `2ea8582`).
- The wave number moved (wave 4 became wave 3).

Checked against the wave-1 code:

- `mise.toml` already has `[tasks.smoke]` running `scripts/cli-smoke.sh`, so
  this plan only has to create that script;
- `Sources/StriaCLI/main.swift` is the 7-line P01 stub that this plan
  replaces;
- `Paths/StriaPaths.swift:StriaPaths.resolve(homeFlag:environment:homeDirectory:currentDirectory:)`
  is the resolver to call;
- `Config/ConfigStore.swift:ConfigStore.loadOrCreate(paths:)` and
  `save(_:paths:)` exist;
- `Errors/StriaError.swift:StriaError.exitCode` gives the exit code mapping.

## Intent and Context

`stria` is a JSON-only tool for AI agents. This plan connects the parser
(P06) to the library facades (P07, P08), implements the exact JSON shapes
and exit codes, replaces the stub `main.swift`, and adds the smoke script
that the acceptance criteria and `mise run smoke` (the existing task in
`mise.toml`) run.

## Non-goals

- No new library behaviour. Use the P07 and P08 facades only.
- No human-readable output, except `--help` and `--version`.
- Do not edit `mise.toml`: its `smoke` task already exists.

## writePaths

- `Sources/StriaCore/CLI/StriaCommand.swift`
- `Sources/StriaCore/CLI/CLIOutputModels.swift`
- `Sources/StriaCore/CLI/Handlers`
- `Sources/StriaCLI/main.swift`
- `scripts/cli-smoke.sh`
- `scripts/make-sample-pdf.swift`
- `Tests/StriaCoreTests/CLI`
- `impl-plans/active/stria-09-cli-commands-smoke.md`

## sharedPaths

- `Sources/StriaCore/CLI/ParsedInvocation.swift`
- `Sources/StriaCore/CLI/CommandLineParser.swift`
- `Sources/StriaCore/CLI/PageListParser.swift`
- `Sources/StriaCore/CLI/Usage.swift`
- `Sources/StriaCore/CLI/CLIJSON.swift`
- `Sources/StriaCore/Config/ConfigKeyPath.swift`
- `Sources/StriaCore/Library`
- `Sources/StriaCore/Integration/LiveServices.swift`
- `mise.toml`

## sharedPathNotes

- `{path: "Sources/StriaCore/CLI/Handlers", intendedEdit: "directory owned by this plan"}`
- `{path: "Sources/StriaCLI/main.swift", intendedEdit: "replace the P01 stub (overview rule 12)"}`
- `{path: "Tests/StriaCoreTests/CLI", intendedEdit: "directory owned by this plan"}`
- `{path: "impl-plans/active/stria-09-cli-commands-smoke.md", intendedEdit: "append to the Progress Log section only"}`
- `{path: "Sources/StriaCore/CLI/ParsedInvocation.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/CLI/CommandLineParser.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/CLI/PageListParser.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/CLI/Usage.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/CLI/CLIJSON.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Config/ConfigKeyPath.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Library", intendedEdit: "read-only; contains the P03, P07 and P08 files"}`
- `{path: "Sources/StriaCore/Integration/LiveServices.swift", intendedEdit: "read-only"}`
- `{path: "mise.toml", intendedEdit: "read-only; its existing smoke task already calls scripts/cli-smoke.sh"}`

## Contracts

```
public enum StriaCommand {
  public typealias ServiceFactory = @Sendable (StriaPaths, StriaConfig) -> (any OCRService, any AgentService)
  public static func run(arguments: [String], environment: [String: String], homeDirectory: URL,
                         currentDirectory: URL, services: ServiceFactory) async -> CommandOutput
}
```

`main.swift` (top-level `await`): call `run` with:

- `Array(CommandLine.arguments.dropFirst())`;
- `ProcessInfo.processInfo.environment`;
- `FileManager.default.homeDirectoryForCurrentUser`;
- the current directory URL;
- `StriaEnvironment.liveServices`.

Then write stdout and stderr through `FileHandle` and call `exit(output.exitCode)`.

## run() Flow

1. `CommandLineParser.parse`. A `usageError` returns `CLIJSON.failure`.
2. `.help(topic)` writes the plain `Usage.text` to stdout with exit 0, and
   `.version` writes `Version.current` with exit 0. Neither resolves the
   data root, creates directories or loads config.
3. Resolve the paths with `StriaPaths.resolve(homeFlag: invocation.home,
   environment:, homeDirectory:, currentDirectory:)`. Then
   `ConfigStore.loadOrCreate(paths:)`, which creates the root and the
   default config lazily.
4. Build a `StriaEnvironment` with `services(paths, config)`. Its
   `onRunLogFailure` stores the first message in a lock-protected box
   (`OSAllocatedUnfairLock` or `Mutex`). Then `StriaLibrary.open`.
5. Dispatch to the handler. On success, if a run-log warning was captured,
   set `stderr` to `warning: run log append failed: <msg>\n`. stdout still
   holds the single JSON object.
6. A `StriaError` becomes `CLIJSON.failure`. Any other error becomes
   `ioError` with `String(describing:)`.

## Handlers (`CLI/Handlers/`, split into three files)

**`DocumentCommands.swift`**

- `import`: resolve the path against `currentDirectory`, then
  `importDocument(at:runOCR: !noOCR)`, then `ImportOutput`.
- `ocr`:
  - pages: `PageListParser.parse(pages, pageCount: document.pageCount)`,
    giving `.pages`;
  - otherwise `retryFailed ? .pendingAndFailed : .pending`;
  - `runOCR` then `OCROutput`;
  - if `unavailableReason` is set, return `failure(serviceUnavailable,
    reason)` with exit 4.
- `list`: `listDocuments(.importedDescending)`.
- `show`: the document summary plus `sha256`, `byteSize`, `renderDpi`,
  `imageFormat`, `ocrVendor`, `ocrModel`, and the outline.
- `page image`: `pageImage(output:)`, resolving `output` against
  `currentDirectory`. `format` is always `"png"`.
- `page text`: `text` is null unless the status is `done`.

**`QueryCommands.swift`**

- `search`: a limit outside `1...100` is `usageError`; otherwise delegate.
- `ask`: map the arguments to a context:
  - `--doc` and `--page` give `.page`;
  - `--doc` alone gives `.document(anchor: nil)`;
  - neither gives `.library`.
  `threadId` is nil. Pass `query` as `AskRequest.retrievalQuery` and `limit`
  as `AskRequest.limit` unchanged (nil when absent); range validation of
  `limit` is done by P08 (`usageError`, exit 2), so do not re-validate here.
  A `serviceFailed` error passes through as exit 5, and the exchange is
  already persisted by P08.
- `history`: a `limit` default of 50.

**`ConfigCommands.swift`**

- `config get [key]` returns the whole `StriaConfig`, or `{key, value}`.
- `config set` calls `ConfigKeyPath.setting`, then `ConfigStore.save`, and
  returns `{key, value}`.
- `paths` returns `{home, database, originals, cache, config, logs}` as
  absolute path strings.

## Output Models (`CLIOutputModels.swift`)

Each model has a custom `encode(to:)` that writes every key, using
`encodeNil` for absent values. The key sets must match `command.md`
exactly:

- `ImportOutput {alreadyImported, document, ocr{status, reason, done, failed, pending}}`
- `OCROutput {docId, processed, done, failed, pending, failures[{page, error}]}`
- `ListOutput {documents}`
- `ShowOutput {document{id, title, pageCount, importStatus, importedAt, originalPath, ocr, sha256, byteSize, renderDpi, imageFormat, ocrVendor, ocrModel}, outline}`
- `PageImageOutput {docId, page, path, width, height, format, cached}`
- `PageTextOutput {docId, page, ocrStatus, text, ocrError, ocrVendor, ocrModel}`
- `SearchOutput {query, matchMode, results[{docId, title, page, snippet, score, imagePath, imageCached}]}`
- `AskOutput {threadId, answer, vendor, model, runId, citations[{docId, title, page, imagePath}]}`
- `HistoryOutput {messages[{id, threadId, role, status, content, docId, page, vendor, model, runId, citations[{docId, page}], createdAt}]}`
- `ConfigValueOutput {key, value}`
- `PathsOutput {home, database, originals, cache, config, logs}`

## Smoke Script

**`scripts/make-sample-pdf.swift`**

- Run as `swift scripts/make-sample-pdf.swift <out.pdf> <a|b>`.
- Uses CoreGraphics and CoreText with the font "Hiragino Sans". Writes 3
  pages with distinct English and Japanese text per page.
- Variant `b` page 2 contains the unique phrase `zebra quantum lattice`.
- Both variants contain the 2-character Japanese word `学習` on page 1.
- Exits non-zero on failure.

**`scripts/cli-smoke.sh`** (`#!/usr/bin/env bash`, `set -euo pipefail`,
executable)

1. Record whether `$HOME/.local/stria` exists.
2. `swift build --product stria`, then
   `BIN="$(swift build --show-bin-path)/stria"`.
3. `WORK=$(mktemp -d)`, `export STRIA_HOME="$WORK/home"`, and a `trap` that
   removes `$WORK`.
4. Generate `a.pdf` and `b.pdf`.
5. `import a.pdf --no-ocr` and `import b.pdf --no-ocr`, extracting
   `document.id`.
6. `list`: assert the documents count is 2.
7. `page image <idA> 1`: assert `path` exists.
8. `config set ocr.vendor pdf-text-layer`, then `ocr <idA>` and
   `ocr <idB>`.
9. `search "zebra quantum lattice"`: assert `results.0.docId == idB` and
   `results.0.page == 2`.
10. `search 学習`: assert `matchMode == like` and at least 1 result.
11. `history`: assert exit 0 and that the `messages` key exists.
12. Assert `$HOME/.local/stria` did not appear if it was absent before.
13. Print `SMOKE OK`.

- Save each command's stdout to `$WORK/<step>.json`, and read values with
  `/usr/bin/plutil -extract <keypath> raw -o - <file>`. For arrays, `raw`
  prints the element count; confirm this on the host and fall back to
  `/usr/bin/python3 -c` when needed.
- Every step checks the exit code, and the script fails fast with the step
  name.

## Pitfalls

- Use `encodeNil`, never `encodeIfPresent`. Absent values must appear as
  `null`.
- stdout must contain exactly one JSON object and a newline. Never `print`
  debug output.
- `--help` and `--version` must not create the data root. A test asserts
  this.
- The tests must pass `--home <temp>` and an `environment` without
  `STRIA_HOME` pointing to a real location. They must never call
  `liveServices`.
- `ask` from the CLI always creates a new thread.
- The smoke script must never use the real data root. It sets `STRIA_HOME`
  before the first `stria` call.

## Tests (`Tests/StriaCoreTests/CLI/`)

All tests call `StriaCommand.run` with a services factory that returns
fakes.

`CLIEndToEndTests` (the acceptance "fake / test hook" flow):

- import two generated PDFs with `--no-ocr` -> exit 0, ids returned
- `list` -> 2 documents
- `page image <id> 1` -> exit 0, and `path` exists
- `ocr <id>` with a `FakeOCRService` scripted with page-specific text -> exit 0, done 3
- `search <phrase unique to doc2 p2>` -> top result is doc2 p2
- `ask "q" --doc <id2> --page 2` -> exit 0 with an answer and citations
- `history --doc <id2> --page 2` -> 2 messages
- `history` -> at least 2

`CLICommandTests`:

- each command's stdout parsed with `JSONSerialization` -> exact key set per the Output Models list (nested keys too)
- unknown doc -> exit 3 `documentNotFound`
- page 99 -> exit 3 `pageNotFound`
- `search` limit 0 -> exit 2
- bad option -> exit 2, stdout empty, stderr parses as the error envelope
- `ocr` with fake unavailable -> exit 4, pages still pending
- `ask` with fake failed -> exit 5; `history` shows the error message
- `ask "q" --doc <id2> --query "<phrase unique to doc2 p2>" --limit 1` -> exit 0; the `FakeAgentService` recorded request has exactly 1 context page, doc2 page 2
- `ask "q" --limit 11` -> exit 2 `usageError`
- `--help` and `--version` -> the temp root does not exist afterwards
- `paths` -> every value starts with the temp root
- `config set render.dpi 10` -> exit 2, config file bytes unchanged
- `config set ocr.concurrency 4` then `config get ocr.concurrency` -> 4
- `--home` beats `STRIA_HOME` in the injected environment
- `import --no-ocr` twice -> second `alreadyImported` true
- slashes in `path` are not escaped

## Verification

- `swift build` -> exit 0 (`tmp/verify/P09/build.log`)
- `swift test --filter CLIEndToEndTests` and `--filter CLICommandTests` -> pass (`tmp/verify/P09/test.log`)
- `bash -n scripts/cli-smoke.sh` -> exit 0
- `scripts/cli-smoke.sh` -> exit 0 and prints `SMOKE OK` (`tmp/verify/P09/smoke.log`)
- The acceptance command chain, run manually with
  `STRIA_HOME=$(mktemp -d)` and `swift run stria`: `import <generated.pdf>
  --no-ocr`, `list`, `page image <docId> 1`, `search <query>`, `history`.
  Every command exits 0 (`tmp/verify/P09/acceptance.log`).
- `swiftlint lint` on this plan's Swift files -> exit 0

## Done Criteria

- [ ] Every command in `command.md` works with the exact JSON keys and exit
  codes.
- [ ] `main.swift` is thin.
- [ ] The smoke script passes with a temp root.
- [ ] The end-to-end test covers the fake OCR, search, ask and history
  flow.

## Progress Log

- (worker appends entries here)
