# P01 Foundation: Rename, Package, agent-gateway Gate G1, Shared Contracts

**Status**: Ready
**planId**: P01
**Wave**: 1
**dependsOn**: none
**Design Reference**: `design-docs/specs/architecture.md#package-layout`, `#data-root`, `#testing-strategy`; `design-docs/specs/design-agent-integration.md#service-boundary`, `#agent-gateway-integration`, `#config`; `design-docs/specs/command.md#global-rules` (exit codes)

## Intent and Context

The repository is an ign SwiftPM scaffold named KaibaViewer
(`Package.swift`, `Sources/KaibaViewerCore/{Version,Command}.swift`,
`Sources/KaibaViewerCLI/main.swift`,
`Tests/KaibaViewerCoreTests/CommandTests.swift`). This plan:

- renames the Swift side to stria;
- adds the agent-gateway dependency and runs implementation gate G1;
- creates every shared type that wave-2 and later plans compile against:
  paths, config, errors, domain models, service protocols, environment, and
  test support (temp roots, sample PDFs, fakes).

Every later plan depends on the exact names below, so do not rename them.

## Non-goals

- No SQLite code (P03).
- No rendering or codec code (P04).
- No gateway adapters (P05).
- No CLI parsing (P06) or handlers (P09).
- No SwiftUI beyond a stub (P11).
- Do not touch README.md, AGENTS.md, mise.toml, scripts/, packaging/, .ign/,
  .github/ or the skills (P02 owns them).
- Do not modify `/Users/taco/gits/tacogips/agent-gateway`. Do not add riela.

## writePaths

- `Package.swift`
- `Package.resolved`
- `Sources/KaibaViewerCore`
- `Sources/KaibaViewerCLI`
- `Tests/KaibaViewerCoreTests`
- `Sources/StriaCore/Version.swift`
- `Sources/StriaCore/Paths/StriaPaths.swift`
- `Sources/StriaCore/Config/StriaConfig.swift`
- `Sources/StriaCore/Config/ConfigStore.swift`
- `Sources/StriaCore/Errors/StriaError.swift`
- `Sources/StriaCore/Models`
- `Sources/StriaCore/Services/ServiceTypes.swift`
- `Sources/StriaCore/OCR/OCRService.swift`
- `Sources/StriaCore/Agent/AgentService.swift`
- `Sources/StriaCore/Library/StriaEnvironment.swift`
- `Sources/StriaCLI/main.swift`
- `Sources/StriaApp/StriaAppMain.swift`
- `Tests/StriaCoreTests/Support`
- `Tests/StriaCoreTests/Foundation`
- `design-docs/references/agent-gateway-c7f2697.md`
- `impl-plans/active/stria-01-foundation-contracts.md`

## sharedPaths

- none

## sharedPathNotes

- `{path: "Sources/KaibaViewerCore", intendedEdit: "delete the directory (scaffold rename)"}`
- `{path: "Sources/KaibaViewerCLI", intendedEdit: "delete the directory (scaffold rename)"}`
- `{path: "Tests/KaibaViewerCoreTests", intendedEdit: "delete the directory (scaffold rename)"}`
- `{path: "Sources/StriaCore/Models", intendedEdit: "directory"}`
- `{path: "Sources/StriaCLI/main.swift", intendedEdit: "temporary stub; P09 replaces it"}`
- `{path: "Sources/StriaApp/StriaAppMain.swift", intendedEdit: "temporary stub; P11 replaces it"}`
- `{path: "Tests/StriaCoreTests/Support", intendedEdit: "directory"}`
- `{path: "Tests/StriaCoreTests/Foundation", intendedEdit: "directory"}`
- `{path: "impl-plans/active/stria-01-foundation-contracts.md", intendedEdit: "append to the Progress Log section only"}`

## Tasks

### TASK-001: Rename and Package.swift

- Move `Sources/KaibaViewerCore/Version.swift` to
  `Sources/StriaCore/Version.swift` with plain `mv`, not `git mv`. Keep
  `Version.current = "0.1.0"`.
- Delete `Sources/KaibaViewerCore/Command.swift`, the
  `Sources/KaibaViewerCLI/` directory and the `Tests/KaibaViewerCoreTests/`
  directory. P06 and P09 replace their behaviour.
- Rewrite `Package.swift`. Keep `// swift-tools-version: 6.0`,
  `platforms: [.macOS(.v14)]` and `swiftLanguageModes: [.v6]`, and set:
  - package name `stria`;
  - products `.library(name: "StriaCore", targets: ["StriaCore"])`,
    `.executable(name: "stria", targets: ["StriaCLI"])` and
    `.executable(name: "stria-app", targets: ["StriaApp"])`;
  - dependency `.package(url: "https://github.com/tacogips/agent-gateway.git", revision: "c7f269753ec36aca92d429ec13316ba033128967")`;
  - target `StriaCore` with dependencies
    `.product(name: "AgentGateway", package: "agent-gateway")`,
    `.product(name: "AgentGatewayAppCore", package: "agent-gateway")` and
    `.product(name: "ACP", package: "agent-gateway")`. Use the package
    identity that SwiftPM reports; it is normally `agent-gateway`;
  - `StriaCLI` executable depends on `StriaCore`;
  - `StriaApp` executable depends on `StriaCore`;
  - `StriaCoreTests` test target depends on `StriaCore`.
- `Sources/StriaCLI/main.swift` stub: print `Version.current` for
  `--version`, otherwise print `Usage: stria <command>`, and exit 0. Import
  `StriaCore`.
- `Sources/StriaApp/StriaAppMain.swift` stub: `@main struct StriaReaderApp:
  App` with a `WindowGroup { Text("stria") }`. Do not name the type
  `StriaApp`, because a type named the same as its module breaks qualified
  lookup.

### TASK-002: Gate G1 (agent-gateway)

1. Run `swift package resolve` (log to `tmp/verify/P01/resolve.log`).
2. Read `.build/checkouts/agent-gateway` (Package.swift and the public
   sources of AgentGateway, AgentGatewayAppCore and ACP). Write
   `design-docs/references/agent-gateway-c7f2697.md` with the confirmed
   declarations, copied as signatures only (no bodies):
   - `GatewayVendor` and its raw values;
   - the `GatewayAgentDefaults` init;
   - `GatewayACPAgent` init(s) and `ProductionGatewayExecutor(environment:)`;
   - `ACPClientConnection.inProcess(agent:)`;
   - `initialize`, `newSession`, `ACPNewSessionRequest`;
   - `promptCollecting`, `ACPPromptRequest`, `ACPPromptResult`, and the
     stop-reason type and its cases;
   - the content-block type used for text, plus `gatewayImageContentBlocks`
     and `GatewayClientImageInput` (`.filePath` and `.data`), and which
     vendors honour `.filePath`;
   - the error type thrown when a CLI vendor executable cannot be launched,
     if one exists.
   Also list where each declaration lives (file path in the checkout).
3. Run `swift build` (log `tmp/verify/P01/build.log`). This must compile
   agent-gateway in Swift 6 mode together with the stria targets.
4. If resolve or build of agent-gateway fails:
   - record the command, exit code and log in the reference doc and the
     Progress Log;
   - remove only the agent-gateway dependency and product references from
     `Package.swift` so the stria targets build;
   - write "G1 FAILED: P05 must use Mode B (unavailable services)" at the
     top of the reference doc.
   Do not add a local-path dependency.

### TASK-003: Shared contracts in StriaCore

All types are `public` and `Sendable`, and `Equatable` where it is cheap.
Field names are fixed contracts.

**`Errors/StriaError.swift`**

- `public enum ErrorCode: String, Sendable, Codable` with the cases
  `ioError, databaseError, databaseTooNew, idCollision, configInvalid,
  usageError, invalidPDF, documentNotFound, pageNotFound, noRelevantPages,
  serviceUnavailable, serviceFailed`.
- `public struct StriaError: Error, Equatable, Sendable { public let code:
  ErrorCode; public let message: String; public var exitCode: Int32 }`.
- Exit code mapping: 1 for io, database, databaseTooNew, idCollision and
  configInvalid; 2 for usageError and invalidPDF; 3 for documentNotFound,
  pageNotFound and noRelevantPages; 4 for serviceUnavailable; 5 for
  serviceFailed.
- Static helpers, for example `static func usage(_ message: String) ->
  StriaError`, one per code.

**`Paths/StriaPaths.swift`**

- `public struct StriaPaths: Sendable, Equatable` with `public let root:
  URL` and computed properties `database` (`stria.sqlite`), `originals`,
  `cache`, `config` (`config.json`) and `logs`.
- Methods:
  - `func original(docId:) -> URL` (`originals/<docId>.pdf`);
  - `func cacheDirectory(docId:) -> URL`;
  - `func cachedPage(docId:page:) -> URL`: `page-%04d.png`, so page 12345
    gives `page-12345.png`;
  - `func runLog(for date: Date) -> URL`:
    `logs/agent-runs-yyyy-MM-dd.jsonl`, formatted in UTC;
  - `func ensureDirectories() throws`: creates root, originals, cache and
    logs with POSIX permissions 0700, wrapping failures as `ioError`;
  - `var allLocations: [URL]`.
- `public static func resolve(homeFlag: String?, environment:
  [String: String], homeDirectory: URL, currentDirectory: URL) ->
  StriaPaths`:
  - precedence is a non-empty flag, then a non-empty `STRIA_HOME`, then
    `homeDirectory/.local/stria`;
  - relative paths are resolved against `currentDirectory` and then
    `standardized`;
  - it must never read `ProcessInfo` or `FileManager.homeDirectory` itself.

**`Config/StriaConfig.swift`**

- `public struct StriaConfig: Codable, Equatable, Sendable { var version:
  Int; var render: RenderConfig; var ocr: OCRConfig; var agent:
  AgentConfig }`, with nested types `RenderConfig { dpi: Int, imageFormat:
  ImageFormat, quality: Double, maxPixelDimension: Int }`, `OCRConfig {
  vendor: String, model: String?, apiKeyEnvironment: String?, concurrency:
  Int, prompt: String? }` and `AgentConfig { vendor: String, model: String?,
  apiKeyEnvironment: String?, neighborPages: Int, maxImages: Int,
  maxContextCharacters: Int, systemPrompt: String? }`.
- `static let defaults` uses exactly the values in
  `design-agent-integration.md#config`.
- `public enum KnownVendors`:
  - `static let gateway: [String]` holds the G1-confirmed `GatewayVendor`
    raw values (expected: `claude-code, codex, cursor, cursor-api, openai,
    anthropic, gemini, openrouter`);
  - `static let pdfTextLayer = "pdf-text-layer"`;
  - `static let apiKeyVendors: Set<String> = ["openai", "anthropic",
    "gemini", "openrouter", "cursor-api"]`.
- `func validate() throws(StriaError)` (`configInvalid`) checks:
  - the ranges in the design's config validation table;
  - `apiKeyEnvironment` matches `^[A-Z_][A-Z0-9_]*$` or is nil;
  - vendor is non-empty, and either in `KnownVendors.gateway` or (for
    `ocr.vendor`) equal to `pdf-text-layer`.
- Custom decoding: a missing key takes its default, and an explicit JSON
  `null` on an optional key sets nil. Use `container.contains(key)` before
  `decodeNil`, because `decodeIfPresent` cannot tell a missing key from
  `null`. Unknown keys are ignored.
- Custom encoding writes `null` explicitly for nil optionals. Synthesized
  Codable omits them, which is wrong here.

**`Config/ConfigStore.swift`**

- `public enum ConfigStore`.
- `static func loadOrCreate(paths: StriaPaths) throws -> StriaConfig`:
  - when `config.json` is missing, create the root dir and write the
    defaults atomically;
  - otherwise decode and validate the file and never rewrite it;
  - invalid JSON or values throw `configInvalid` and leave the bytes
    untouched.
- `static func save(_ config: StriaConfig, paths: StriaPaths) throws`:
  validate, encode with sorted keys and pretty printing, then
  `Data.write(options: .atomic)`.

**`Models/` (split by responsibility, one file per bullet)**

- `DomainEnums.swift`, each enum `String` raw-valued:
  - `ImageFormat`: `heic`, `jpeg`;
  - `OCRStatus`: `pending`, `done`, `failed`;
  - `ImportStatus`: `rendering`, `ready`;
  - `ChatScope`: `page`, `nearby`, `document`, `library`;
  - `ChatRole`: `user`, `assistant`;
  - `MessageStatus`: `ok`, `error`;
  - `RunKind`: `ocr`, `ask`;
  - `RunStatus`: `ok`, `failed`;
  - `SearchBackend`: `fts5`, `like`;
  - `MatchMode`: `fts`, `like`;
  - `DocumentOrder`: `importedDescending`, `recents`.
- `StriaDateFormat.swift`: `string(from: Date) -> String` and `date(from:
  String) -> Date?`, using `Date.ISO8601FormatStyle` (UTC, whole seconds,
  for example `2026-10-01T12:00:00Z`).
- `DocumentModels.swift`:
  - `DocumentRecord { id, sha256, title, originalFilename, originalPath
    (relative), byteSize: Int64, pageCount, importStatus, renderDPI,
    imageFormat, ocrVendor?, ocrModel?, outlineJSON?, lastReadPage?,
    lastOpenedAt: Date?, importedAt: Date, updatedAt: Date }`;
  - `OCRCounts: Codable { done, failed, pending }`;
  - `DocumentSummary: Codable { id, title, pageCount, importStatus,
    importedAt: Date, originalPath (absolute string), ocr: OCRCounts }`;
  - `OutlineNode: Codable { title, page: Int?, children: [OutlineNode] }`,
    whose custom encode writes `"page": null`.
- `PageModels.swift`:
  - `PageInfo { documentId, pageNumber, imageFormat, width, height,
    ocrStatus, ocrText?, ocrVendor?, ocrModel?, ocrError?, ocrAttempts,
    ocrUpdatedAt: Date? }`;
  - `StoredPageImage { data: Data, format: ImageFormat, width: Int, height:
    Int }`;
  - `PageRef: Codable, Hashable { docId: String, page: Int }`.
- `SearchModels.swift`: `SearchHit { docId, title, page, snippet, score:
  Double }` and `SearchOutcome { matchMode: MatchMode, hits: [SearchHit] }`.
- `RunModels.swift`: `AgentRunRecord { id: String, kind: RunKind,
  documentId: String?, pageNumber: Int?, vendor: String, model: String?,
  status: RunStatus, error: String?, imageCount: Int, startedAt: Date,
  finishedAt: Date, durationMs: Int }`.
- `ChatModels.swift`:
  - `ChatMessageRecord { id: Int64, threadId, role, status, content,
    documentId?, pageNumber?, vendor?, model?, agentRunId?, citations:
    [PageRef], createdAt: Date }`;
  - `NewChatThread { documentId?, pageNumber?, scope: ChatScope }`;
  - `AskExchange { threadId: String, newThread: NewChatThread?, question:
    String, anchorDocumentId: String?, anchorPage: Int?, assistantStatus:
    MessageStatus, assistantContent: String, vendor: String, model: String?,
    citations: [PageRef], run: AgentRunRecord, createdAt: Date }`.
- `ImportModels.swift`:
  - `OCRProgress { done, failed, pending, total }`;
  - `ImportOCRStatus` (`completed, partial, skipped, unavailable`);
  - `ImportOCROutcome { status, reason: String?, done, failed, pending }`;
  - `ImportResult { alreadyImported: Bool, document: DocumentSummary, ocr:
    ImportOCROutcome }`;
  - `enum ImportEvent { copied(docId: String), rendered(page: Int, total:
    Int), ocr(OCRProgress), finished(ImportResult), failed(StriaError) }`;
  - `enum OCRSelection { pending, pendingAndFailed, pages([Int]) }`;
  - `OCRFailure { page: Int, error: String }`;
  - `OCRRunSummary { docId, processed: [Int], done, failed, pending,
    failures: [OCRFailure], unavailableReason: String? }`. The counts are
    document-wide after the run, and `processed` lists the pages attempted
    in this run in ascending order;
  - `enum OCREvent { progress(OCRProgress), finished(OCRRunSummary),
    failed(StriaError) }`.

**`Services/ServiceTypes.swift`**

- `ServiceSettings { vendor: String, model: String?, apiKeyEnvironment:
  String? }`, with `init(ocr: StriaConfig.OCRConfig)` and `init(agent:
  StriaConfig.AgentConfig)`.
- `enum ServiceError: Error, Equatable, Sendable { case unavailable(String),
  failed(String) }`.

**`OCR/OCRService.swift`**

- `protocol OCRService: Sendable { func recognize(_ request: OCRRequest)
  async throws -> OCRResult }`.
- `OCRRequest { docId, page, pngPath: URL, prompt, settings }` and
  `OCRResult { text }`.

**`Agent/AgentService.swift`**

- `protocol AgentService: Sendable { func ask(_ request: AgentRequest) async
  throws -> AgentAnswer }`.
- `AgentRequest { question, systemPrompt, contextPages: [ContextPage],
  history: [ChatTurn], settings }`.
- `ContextPage { docId, title, page, ocrText: String?, pngPath: URL }`,
  `ChatTurn { role: ChatRole, content }` and `AgentAnswer { text }`.

**`Library/StriaEnvironment.swift`**

- `public struct StriaEnvironment: Sendable { paths, config, ocrService: any
  OCRService, agentService: any AgentService, clock: @Sendable () -> Date,
  onRunLogFailure: (@Sendable (String) -> Void)? }`.
- The memberwise-style public init defaults `clock` to `{ Date() }` and
  `onRunLogFailure` to nil.

### TASK-004: Test support (`Tests/StriaCoreTests/Support/`)

- `TestDataRoot.swift`:
  - `func withTestDataRoot<T>(_ body: (StriaPaths) async throws -> T)
    async throws -> T`;
  - it creates `FileManager.default.temporaryDirectory/stria-tests-<UUID>`,
    builds `StriaPaths(root:)`, and removes the directory afterwards, even
    when the body throws;
  - `func makeTestEnvironment(paths:ocr:agent:config:clock:)` returns a
    `StriaEnvironment` with fakes.
- `SamplePDFFactory.swift`: `static func makePDF(at: URL, pages: [String],
  pageSize: CGSize = CGSize(width: 612, height: 792)) throws`. It uses a
  CoreGraphics PDF context plus CoreText (`CTFramesetter`) with the font
  "Hiragino Sans", so both Japanese and English text get a real text layer.
  It also provides `static func writeNotAPDF(at:)`.
- `FakeOCRService.swift`: `actor FakeOCRService: OCRService`.
  - Scripting: `script(docId:page:_ result: Result<String, ServiceError>)`
    and `setDefault(_:)` (default `.success("text <docId> p<page>")`).
  - Introspection: `requests: [OCRRequest]`, `maxInFlight: Int`, and
    `setDelay(nanoseconds:)`.
  - Track in-flight calls by incrementing before `Task.sleep` and
    decrementing after it, so concurrency bounds can be asserted.
- `FakeAgentService.swift`: `actor FakeAgentService: AgentService` with a
  FIFO of scripted `Result<String, ServiceError>` (default `.success("answer
  [<firstDocId> p.<firstPage>]")`) and `requests: [AgentRequest]`.

### TASK-005: Foundation tests (`Tests/StriaCoreTests/Foundation/`)

Use Swift Testing (`import Testing`, `@Test`, `#expect`), imitating the
deleted scaffold `Tests/KaibaViewerCoreTests/CommandTests.swift` style.

`PathsTests`:

- flag "/tmp/a", env STRIA_HOME "/tmp/b" -> root /tmp/a
- flag nil, env STRIA_HOME "/tmp/b" -> /tmp/b
- flag nil, env STRIA_HOME "" -> `<home>/.local/stria`
- flag "rel/x", cwd /tmp/c -> /tmp/c/rel/x
- every `allLocations` entry has the root path as prefix
- `cachedPage(docId:"abc", page:1)` -> filename `page-0001.png`; page 12345 -> `page-12345.png`
- `runLog(for:)` at 2026-10-01T23:30:00Z -> `agent-runs-2026-10-01.jsonl`
- `ensureDirectories()` -> dirs exist with permissions 0700

`ConfigTests`:

- missing file -> file created; decoded value == defaults
- file `{"ocr":{"concurrency":4}}` -> concurrency 4, other values default; file bytes unchanged after load
- `{"ocr":{"model":null}}` -> `ocr.model == nil`
- invalid JSON -> `configInvalid`; bytes unchanged
- dpi 10 -> `configInvalid`
- `apiKeyEnvironment` "sk-abc" -> `configInvalid`
- encoding defaults -> the output contains `"prompt" : null`
- save then load round-trip -> equal

`StriaErrorTests`: every code maps to the exit code in the table.

`SamplePDFTests`: a generated 3-page PDF with Japanese and English text ->
`PDFDocument.pageCount == 3`, and page 2's `string` contains the Japanese
sample.

## Pitfalls

- `swift package resolve` and the first `swift build` are slow, because
  agent-gateway builds once. Wait for them in the foreground.
- Do not reference agent-gateway types anywhere except
  `design-docs/references/agent-gateway-c7f2697.md`. Adapters belong to P05.
- Keep every public type name exactly as written. Wave-2 plans start in
  parallel and compile against them.
- Do not read `ProcessInfo.processInfo.environment` in `StriaPaths` or
  `ConfigStore`.

## Verification

- `swift package resolve` -> exit 0 (`tmp/verify/P01/resolve.log`)
- `swift build` -> exit 0 (`tmp/verify/P01/build.log`)
- `swift test` -> exit 0, with the Foundation suites passing (`tmp/verify/P01/test.log`)
- `swiftlint lint Sources Tests Package.swift` -> exit 0 (`tmp/verify/P01/lint.log`)
- `grep -rn -i kaiba Package.swift Sources Tests` -> no output
- `git status --short` -> changes only inside the writePaths

## Done Criteria

- [ ] `Package.swift` declares products `StriaCore`, `stria` and `stria-app`
  and the agent-gateway revision pin (or the documented G1 failure).
- [ ] `Package.resolved` exists.
- [ ] `design-docs/references/agent-gateway-c7f2697.md` records the
  confirmed API or the failure evidence.
- [ ] All contract types listed above compile with the exact names.
- [ ] Foundation and support tests pass. No test touches `~/.local/stria`.

## Progress Log

- (worker appends entries here: hashes, commands, exit codes, log paths, drift notes)
