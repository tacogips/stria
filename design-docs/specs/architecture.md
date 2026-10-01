# Architecture

## Status

Accepted (stria v0.1 design, commit `72246dd`). Replaces the ign scaffold
description. Wave 1 is implemented and accepted. Wave 2 code exists but is not
accepted. See [Implementation Rollout](#implementation-rollout).

## Overview

`stria` is a macOS 14+ PDF reader with an AI agent pane and an agent-facing
CLI. When you import a PDF, stria keeps the original file, renders every page
to a compressed image stored in SQLite, and OCRs each page through an agent
model. Only the OCR text is indexed. The same store serves three consumers:

- the SwiftUI app (`stria-app`): read PDFs with continuous vertical
  scrolling, navigate by outline, thumbnails or OCR search, and ask an agent
  about the current page or document;
- the CLI (`stria`): a JSON-only tool for external AI agents. An agent
  searches OCR text across all PDFs, fetches the page image and answers. This
  makes stria a RAG backend;
- the built-in OCR and Q&A flows, implemented in Swift in `StriaCore`.
  `agent-gateway` is the only AI library. riela is not used
  (`../user-qa/no-riela-decision.md`).

Detailed specs:

- Storage layout, schema, image pipeline, cache, search: `design-storage.md`
- OCR and agent flows, agent-gateway integration, config, run logs, secrets:
  `design-agent-integration.md`
- CLI contract and agent usage: `command.md`
- App UI, reference readers and view models: `design-app-ui.md`
- User decisions: `../user-qa/no-riela-decision.md` (answered),
  `../user-qa/default-agent-config.md`, `../user-qa/app-distribution.md`
  (pending, defaults applied)

## Package Layout

The SwiftPM package is named `stria`. It uses Swift tools 6.0, Swift 6
language mode and `.macOS(.v14)` only.

| Target | Kind | Product | Responsibility |
| --- | --- | --- | --- |
| `StriaCore` | library | `StriaCore` | All domain logic: paths, config, SQLite store, import, cache, search, OCR and ask coordinators, agent-gateway adapters, CLI parsing and handlers, app view models |
| `StriaCLI` | executable | `stria` | Thin `main.swift` that calls `StriaCommand.run`, writes stdout and stderr, and exits with the returned code |
| `StriaApp` | executable | `stria-app` | SwiftUI scenes and PDFKit `NSViewRepresentable` wrappers only. Binds to view models from `StriaCore` |
| `StriaCoreTests` | test | - | Swift Testing suites that use temp dirs and fake services only |

Dependency: `.package(url: "https://github.com/tacogips/agent-gateway.git",
revision: "c7f269753ec36aca92d429ec13316ba033128967")`. `StriaCore` uses the
products `AgentGateway`, `AgentGatewayAppCore` and `ACP`. There are no other
external dependencies. In particular there is no swift-argument-parser: CLI
parsing extends the scaffold's hand-written style in `StriaCore/CLI`, so the
parser can be unit-tested without an executable target. No further modules are
added. View models live in `StriaCore/AppModel` rather than in a separate
`StriaAppCore` target, because they need the same store and services and a
separate target adds nothing that tests require.

`StriaCore` source folders have one responsibility each, and every file stays
under 1000 lines:

| Folder | Contents |
| --- | --- |
| `Paths/` | `StriaPaths` (data root layout), data-root resolution |
| `Config/` | `StriaConfig` model, defaults, load and save, `config get/set` key paths and validation |
| `Storage/` | SQLite wrapper (system `SQLite3`), migrations, document, page, search, chat and agent-run queries |
| `Import/` | document identity (SHA-256), PDF validation, page renderer, image codec, outline extraction, import coordinator |
| `Cache/` | `PageImageCache` (`cache/<docId>/page-NNNN.png`) |
| `OCR/` | `OCRService` protocol, OCR coordinator (state machine, bounded concurrency), `pdf-text-layer` local service |
| `Agent/` | `AgentService` protocol, context selection, prompt assembly, ask coordinator |
| `Integration/` | `GatewayOCRService`, `GatewayAgentService`, run recorder (agent_runs and JSONL logs), secret redaction |
| `CLI/` | `StriaCommand` parser, per-command handlers, JSON encoding, exit codes |
| `AppModel/` | `@MainActor @Observable` view models for the app |

The composition object `StriaLibrary` is built from `StriaEnvironment { paths,
config, ocrService, agentService, clock }`. It exposes import, OCR, cache,
search, ask, history, reading-state and config operations. The CLI, the app
and the tests all go through it. `StriaEnvironment.live(paths:config:)`
selects the agent-gateway services. Tests inject `FakeOCRService` and
`FakeAgentService`.

## Data Root

The default is `~/.local/stria`. The resolution order is: the `--home <path>`
CLI flag, then the `STRIA_HOME` environment variable, then
`$HOME/.local/stria`. The app has no `--home` flag. The resolver is a pure
function of `(flag, environment dictionary, home directory)`, so tests never
read the real environment or the real home. Relative paths are resolved
against the current directory and then standardized.

```
<root>/stria.sqlite                 main DB (WAL)
<root>/originals/<docId>.pdf        byte-identical copies of imported PDFs
<root>/cache/<docId>/page-NNNN.png  expanded page images, safe to delete
<root>/config.json                  settings (env var names only, no secrets)
<root>/logs/agent-runs-YYYY-MM-DD.jsonl   one line per OCR or agent call
```

Directories are created on first use with mode 0700. Nothing is written
outside `<root>`. A test asserts that every `StriaPaths` location is inside
the root, and every test uses a unique temp root.

## Data Flows

1. Import (app or CLI): validate the PDF, compute SHA-256, check for an
   existing document, copy to `originals/`, insert the document with status
   `rendering`, render and compress each page into `pages` (OCR status
   `pending`), store the outline, set the document to `ready`, then start the
   OCR coordinator unless `--no-ocr` is set or OCR is unavailable.
2. OCR: for each selected page, expand it to the PNG cache, send the PNG and
   the OCR prompt through `OCRService`, then store the text and FTS row
   (`done`) or the error (`failed`). Every call is recorded in `agent_runs` and
   `logs/`.
3. Open in app: load `originals/<docId>.pdf` into `PDFView` for display, then
   expand all stored page images into the cache in the background. The cache
   images are not displayed.
4. Ask (app or CLI): choose the context pages, expand their images, and send
   the question, OCR text, PNG images and thread history through
   `AgentService`. Persist the user and assistant messages and the run.
5. External agent (CLI): run `stria search`, then `stria page image`, let the
   model read the PNG and answer. Alternatively, `stria ask` returns the
   built-in RAG answer.

## Concurrency Model

- `StriaStore` is an actor that owns one SQLite connection per process (WAL,
  `busy_timeout` 5000 ms, `foreign_keys=ON`). This lets the app and a CLI
  process share the DB.
- Rendering is sequential per document inside one task. PDFKit objects are not
  `Sendable`, so a `PDFDocument` is created and used inside that task only.
- OCR and cache expansion use a `TaskGroup` bounded by the configured
  concurrency.
- The UI never awaits import or OCR. View models observe progress through
  `AsyncStream`.

## Testing Strategy

- Tests use Swift Testing in `StriaCoreTests`. Every test builds `StriaPaths`
  from a unique `FileManager.default.temporaryDirectory` subdirectory and
  removes it afterwards. The shared helper `withTestDataRoot` creates that
  root directory (mode 0700) before the test body runs, because fixtures
  write input files such as generated PDFs directly into it, and
  `CGDataConsumer(url:)` cannot create a file in a missing directory. It
  creates only the root. `originals/`, `cache/` and `logs/` are still created
  by production code (`StriaPaths.ensureDirectories` or first use), so tests
  of that behaviour stay meaningful.
- PDFs are generated in-test with CoreGraphics (a `CGContext` PDF plus
  CoreText), with distinct English and Japanese text per page.
- `FakeOCRService` and `FakeAgentService` record requests and return scripted
  results or errors. Tests use no network and no vendor credentials, and
  never execute agent-gateway calls.
- App behaviour is tested through the `AppModel/` view models.
- When the host SQLite lacks FTS5 trigram support, FTS-specific assertions are
  skipped and the LIKE backend is tested instead. The LIKE backend is also
  tested on every host by forcing it (`design-storage.md#search-backend`).

Required test coverage:

| Area | Cases |
| --- | --- |
| Paths | precedence flag > `STRIA_HOME` > home default; all locations are inside the root |
| Identity / import | same bytes give the same `docId`; a second import returns `alreadyImported` and adds no rows; an interrupted `rendering` import resumes; a non-PDF gives `invalidPDF` |
| Render / codec | HEIC (or the JPEG fallback) and forced JPEG round-trips keep width and height; the pixel cap is applied |
| Cache | expansion writes a valid PNG; a valid file is not rewritten; a corrupt file is rewritten |
| Migrations | fresh DB becomes v1; reopening is a no-op; a newer `user_version` gives `databaseTooNew`; the backend is recorded in `meta` |
| Search | English and Japanese `fts` hits; a 2-character Japanese `like` hit; cross-document results with the correct doc and page; `--doc` filter; LIKE escaping of `%` and `_`; forced LIKE backend |
| OCR | state machine transitions including `--retry-failed` and `--pages`; `unavailable` leaves pages `pending`; the concurrency bound is respected; FTS is updated on `done`; one `agent_runs` row per call |
| Ask / chat | context selection per scope; persistence of ok and failed exchanges; nothing is persisted for `unavailable` or `noRelevantPages`; per-page and per-PDF history |
| Config | defaults are created on first run; a partial file gets defaults; `set` validation and the `apiKeyEnvironment` pattern; invalid JSON is left untouched |
| CLI | argument parsing and usage errors; JSON key set and exit code per command; end-to-end flow |
| Secrets | error redaction replaces the resolved value; no secret value appears in config, DB, logs or JSON output |
| View models | jump parsing and clamping; current outline node; last-read restore; scope indicator; citation chip parsing; history modes |

## Implementation Rollout

Status: wave 1 is done in commit `2ea8582`. It covers P01 (foundation
contracts: `Paths/`, `Config/`, `Errors/`, `Models/`, the `OCRService` and
`AgentService` protocols, `StriaEnvironment`, test fakes and the sample PDF
factory) and P02 (the rename below). The remaining plans P03-P11 build on
those contracts and do not redefine them. Their dependency order is:

| Plan | Scope | Depends on |
| --- | --- | --- |
| P03 | `Storage/` (SQLite wrapper, migration 1, search backend, queries), `StriaLibrary` core | P01 |
| P04 | `Import/` renderer and image codec, `Cache/` | P01 |
| P05 | `Integration/` (gateway services, run recorder, redaction), `pdf-text-layer` | P01 |
| P06 | `CLI/` parser, JSON encoding, exit codes, config keys | P01 |
| P07 | Import and OCR coordinators (`StriaLibrary` extensions) | P03, P04, P05 |
| P08 | Search, ask retrieval and coordinator, history (`StriaLibrary` extensions) | P03, P04, P05 |
| P09 | CLI command handlers, `main.swift`, smoke script | P05, P06, P07, P08 |
| P10 | `AppModel/` view models | P07, P08 |
| P11 | `StriaApp` SwiftUI views and PDFKit wrapper | P10 |

Wave 2 status: commit `0082491` contains unreviewed code for P03-P06. `swift
build` passes, swiftlint reports 0 violations, and `swift test` has 7
failures out of 51. Those plans are re-issued as stabilization plans. Each
one fixes the failing tests it owns by fixing behaviour, finishes any
requirement from its original plan text that is still missing, and passes
the test-integrity and adversarial review gates before acceptance. The
known failures and their design-level fixes:

| Owner | Failing tests | Fix (design rule) |
| --- | --- | --- |
| P04 | `IdentityTests`, `InspectorTests`, `OutlineTests`, `RenderCodecTests` | `withTestDataRoot` creates the root first ([Testing Strategy](#testing-strategy)). P04 owns `Tests/StriaCoreTests/Support/` in the stabilization wave |
| P03 | `SearchQueryBuilderTests.quotingTrigramsAndSnippets` | The builder already follows the dedup-then-cap rule (`design-storage.md#fuzzy-retrieval-ask`). The test's cap case is corrected to use a question with more than 64 distinct trigrams, and the test also asserts that the repeated question yields exactly 4 |
| P05 | `LiveRoutingTests.routesPDFTextLayerOffline` | `pdf-text-layer` NFKC-normalizes the extracted text (`design-agent-integration.md#pdf-text-layer-local-service`). The assertion is unchanged |

P07-P11 start only after the P03-P06 stabilization wave passes `swift build
--build-tests` and `swift test`. Because every plan shares the one
`StriaCoreTests` target, an implementer finishes only after `swift build
--build-tests` passes with its own files and its focused tests have been
re-run at the end of its run. If another plan's file breaks the build, the
implementer waits and re-runs before reporting a blocker.

Rules for every plan and dispatch manifest:

- `writePaths`, `sharedPaths` and `trackedPaths` list only repository source
  paths (`Sources/`, `Tests/`, `scripts/`, `design-docs/`, `impl-plans/`,
  `README.md`, `Package.swift`, `mise.toml`, `.swiftlint.yml`). They never
  list `.build/` or anything under it (including
  `.build/checkouts/agent-gateway`), other build outputs (`dist/`), `tmp/`,
  or any directory that contains a nested `.git`. The agent-gateway API is
  referenced through `../references/agent-gateway-c7f2697.md`.
- Within one wave, plans have disjoint `writePaths`. A file that two plans
  need (for example `Tests/StriaCoreTests/Support/`) has one owner per wave.
- Declared paths stay small: each file is at most 8 MB and the total at most
  64 MB. Test PDFs and page images are generated at test time in temp
  directories and are never committed.

## Rename and Repository Changes

Done in wave 1 (`2ea8582`). Every `KaibaViewer` / `kaiba-viewer` name became
`stria`:

- `Package.swift`, `Sources/`, `Tests/`; `Command.swift` becomes `StriaCommand`
- README.md, plus the AGENTS.md project overview and commands
- `mise.toml` tasks: `run` becomes `swift run stria`; new `run:app` runs
  `swift run stria-app`; new `smoke` runs `scripts/cli-smoke.sh`; tap paths
  become `Formula/stria.rb` and `Casks/stria.rb`
- `scripts/*.sh` product and artifact names, and URLs (`tacogips/stria`)
- `packaging/homebrew/README.md`
- `.ign/ign-var.json` and `.ign/ign-files.json`
- the `.claude/` and `.codex/` release skills

Release scripts keep shipping the CLI binary only, now as product `stria`.

`.github/workflows/linux-amd64-build.yml` is removed. stria depends on PDFKit,
SwiftUI and ImageIO and is macOS-only by requirement, so the Linux build of
the product cannot succeed. `gitleaks.yml` stays.

## Release Surfaces

- Homebrew formula archives under `dist/homebrew/` (CLI `stria`).
- Signed and notarized Cask DMGs under `dist/homebrew-cask/` (CLI `stria`).
- `stria-app` runs with `swift run stria-app`. `.app` bundling is deferred
  (`../user-qa/app-distribution.md`).
