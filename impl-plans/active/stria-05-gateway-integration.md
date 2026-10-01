# P05 agent-gateway Adapters, Live Services, pdf-text-layer, Redaction, Run Log Writer

**Status**: Ready (re-issued in session 243)
**planId**: P05
**Wave**: 1 of the session-243 manifest
**dependsOn**: none in this manifest (builds on completed P01, commit `2ea8582`)
**Design Reference**: `design-docs/specs/design-agent-integration.md#service-boundary`, `#run-records`, `#pdf-text-layer-local-service`, `#prompt`, `#agent-gateway-integration` (including the pre-call checks), `#secrets`; `design-docs/specs/architecture.md#implementation-rollout`; `design-docs/references/agent-gateway-c7f2697.md` (authoritative for signatures)

## Session-243 Revision

- The session-241 fanout failed because this plan declared
  `.build/checkouts/agent-gateway` as a sharedPath. That entry is removed.
  No path under `.build/` may be declared, in this plan or in its Progress
  Log requests (`design-docs/specs/architecture.md#implementation-rollout`).
- Gate G1 is done. `design-docs/references/agent-gateway-c7f2697.md` holds
  the confirmed API and does not start with "G1 FAILED", and P01 already
  built the package with the dependency. **Mode A is therefore mandatory.**
  The old Mode B (the `UnavailableOCRService` / `UnavailableAgentService`
  fallbacks) is dropped.
- The design adds a pre-call check: vendor `cursor-api` is `unavailable`,
  because it rejects gateway image inputs at c7f2697.
- `GatewayProcessError.launchFailed` is the confirmed executable-launch
  error.

## Intent and Context

This plan implements the production `OCRService` and `AgentService` on top
of agent-gateway, the offline `pdf-text-layer` OCR service, secret
redaction, and the JSONL run log writer. It also provides the
`StriaEnvironment.live` / `liveServices` factory that the CLI (P09) and the
app (P11) use.

Tests never call agent-gateway, because tests run without network or
credentials. Every gateway-touching function is therefore split into:

- a pure part that is tested: preflight, settings mapping, prompt part
  ordering, redaction;
- a thin call part that is not tested.

Existing code to imitate:

- `Sources/StriaCore/Services/ServiceTypes.swift:ServiceSettings`,
  `ServiceError` (use them as-is);
- `Sources/StriaCore/Config/StriaConfig.swift:KnownVendors` (`gateway`,
  `pdfTextLayer`, `apiKeyVendors`);
- `Sources/StriaCore/Paths/StriaPaths.swift:StriaPaths.runLog(for:)`,
  `ensureDirectories()` (0700 directories);
- `Tests/StriaCoreTests/Support/TestDataRoot.swift:withTestDataRoot` and
  `SamplePDFFactory.makePDF(at:pages:)` for tests.

## Non-goals

- No coordinators: no page state, chat persistence or agent_runs rows (P07
  and P08 own those).
- No streaming, no per-call timeout, no session reuse.
- No riela.
- No Mode B or unavailable fallback services.
- Do not modify `Package.swift`, `Package.resolved` or
  `Sources/StriaCore/Config/StriaConfig.swift`. `cursor-api` stays a valid
  config value; only the preflight rejects it.

## writePaths

- `Sources/StriaCore/Integration`
- `Sources/StriaCore/OCR/PDFTextLayerOCRService.swift`
- `Tests/StriaCoreTests/Integration`
- `impl-plans/active/stria-05-gateway-integration.md`

## sharedPaths

- `design-docs/references/agent-gateway-c7f2697.md`
- `Sources/StriaCore/Services/ServiceTypes.swift`
- `Sources/StriaCore/OCR/OCRService.swift`
- `Sources/StriaCore/Agent/AgentService.swift`
- `Sources/StriaCore/Library/StriaEnvironment.swift`
- `Sources/StriaCore/Config/StriaConfig.swift`
- `Sources/StriaCore/Models`
- `Sources/StriaCore/Paths/StriaPaths.swift`
- `Tests/StriaCoreTests/Support`

## sharedPathNotes

- `{path: "Sources/StriaCore/Integration", intendedEdit: "directory"}`
- `{path: "Tests/StriaCoreTests/Integration", intendedEdit: "directory"}`
- `{path: "impl-plans/active/stria-05-gateway-integration.md", intendedEdit: "append to the Progress Log section only"}`
- `{path: "design-docs/references/agent-gateway-c7f2697.md", intendedEdit: "read-only; reference owned by P01"}`
- `{path: "Sources/StriaCore/Services/ServiceTypes.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/OCR/OCRService.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Agent/AgentService.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Library/StriaEnvironment.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Config/StriaConfig.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Models", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Paths/StriaPaths.swift", intendedEdit: "read-only"}`
- `{path: "Tests/StriaCoreTests/Support", intendedEdit: "read-only; test helpers owned by completed P01"}`

## Files and Contracts

**`Integration/SecretRedactor.swift`**

- `public enum SecretRedactor`.
- `static func redact(_ text: String, secrets: [String]) -> String`:
  replaces each non-empty secret with `[REDACTED]`, then truncates.
- `static func truncate(_ text: String, limit: Int = 2000) -> String`:
  cuts at a Character boundary.

**`Integration/GatewayPreflight.swift`**

- `struct PreflightResult { vendor: GatewayVendor, secretValue: String? }`.
- `static func check(_ settings: ServiceSettings, environment: [String: String]) throws(ServiceError) -> PreflightResult`
  throws `unavailable` with a message naming the problem. Check in this
  order and stop at the first failure:
  - the vendor is not a `GatewayVendor` raw value: "unknown vendor <v>";
  - the vendor is `cursor-api` (`GatewayVendor.cursorAPI`):
    "vendor cursor-api does not support image input". Check this before the
    model and key checks, so the reason is stable whatever the other
    settings are;
  - the vendor is in `KnownVendors.apiKeyVendors` and `model` is nil:
    "model is required for vendor <v>";
  - the vendor is in `KnownVendors.apiKeyVendors` and `apiKeyEnvironment`
    is nil: "apiKeyEnvironment is required for vendor <v>";
  - `apiKeyEnvironment` is set but `environment[name]` is nil or empty:
    "environment variable <NAME> is not set". Name the variable, never the
    value.

**`Integration/GatewayPromptParts.swift`**

- `enum PromptPart: Equatable { case text(String), image(URL) }`.
- `static func ocrParts(_ request: OCRRequest) -> [PromptPart]`: returns
  `[.text(prompt), .image(pngPath)]`.
- `static func agentParts(_ request: AgentRequest) -> [PromptPart]`, in this
  order:
  1. if `history` is non-empty, `.text("Previous conversation:\n" + turns as
     "User: ..." / "Assistant: ...")`;
  2. for each context page, `.text("Document \"<title>\" (<docId>) page
     <page>\n" + (ocrText ?? "OCR text not available"))` followed by
     `.image(pngPath)`;
  3. `.text(question)`.

**`Integration/GatewayPromptRunner.swift`** (not unit-tested; it needs a real vendor)

- `func run(settings:systemPrompt:parts:cwd:environment:) async throws ->
  String`, following `design-agent-integration.md#agent-gateway-integration`
  steps 1-6:
  1. build the defaults: `GatewayAgentDefaults(vendor:model:systemPrompt:apiKeyEnvironment:...)`,
     with the remaining parameters at their defaults;
  2. `GatewayACPAgent(defaults:executor: ProductionGatewayExecutor(environment:))`;
  3. `ACPClientConnection.inProcess(agent:)`;
  4. `initialize`, then `newSession(cwd: paths.cache path)`;
  5. `promptCollecting` with the prompt parts in order: `.text(s)` becomes
     `ACPContentBlock.text(s)`, and `.image(url)` becomes the blocks from
     `try gatewayImageContentBlocks([.filePath(url.path)])`. Always use
     `.filePath`, because `gatewayImageContentBlocks` already reads the file
     and inlines it as base64 for every supported vendor;
  6. a `result.response.stopReason` other than `.endTurn` becomes
     `ServiceError.failed("stop reason: <rawValue>")`. On `.endTurn`,
     return `result.messageText`.
- Map errors:
  - `GatewayProcessError.launchFailed` (when it surfaces typed) becomes
    `unavailable("vendor executable could not be launched: <vendor>")`. If
    the in-process ACP layer wraps it so it cannot be matched by type, map
    it to `failed` and record that in the Progress Log. Do not match on
    error strings;
  - any other thrown error, including a throw from
    `gatewayImageContentBlocks`, becomes
    `failed(SecretRedactor.redact(String(describing: error), secrets: [secretValue].compactMap { $0 }))`.
- Use the exact API names from the reference doc. If the compiler rejects a
  name, read the matching file under the SwiftPM checkout read-only (see
  Pitfalls), follow the real signature, and record the difference in the
  Progress Log for the serial step to copy into the reference doc. Do not
  edit the reference doc yourself.

**`Integration/GatewayOCRService.swift`**

- `public struct GatewayOCRService: OCRService { init(paths: StriaPaths,
  environment: [String: String]) }`.
- Run preflight, then the runner with no system prompt and `ocrParts`.
  Return `OCRResult(text: messageText)`. Do not post-process; P07 does that.

**`Integration/GatewayAgentService.swift`**

- `public struct GatewayAgentService: AgentService` with the same init.
- Run preflight, then the runner with `systemPrompt: request.systemPrompt`
  and `agentParts`.

**`OCR/PDFTextLayerOCRService.swift`**

- `public struct PDFTextLayerOCRService: OCRService { init(paths: StriaPaths) }`.
- Open `paths.original(docId:)` with `PDFDocument`, take
  `page(at: page - 1)?.string ?? ""`, and return it.
- A missing file or page throws `ServiceError.failed("page not available")`.
- The PDFDocument is created inside the call and not stored.

**`Integration/LiveServices.swift`**

- `struct LiveOCRService: OCRService` (`init(paths:environment:)`): routes to
  `PDFTextLayerOCRService` when `request.settings.vendor ==
  KnownVendors.pdfTextLayer`, otherwise to `GatewayOCRService`. Routing is
  per request, so a config change takes effect without a rebuild.
- The agent side needs no router: `liveServices` returns
  `GatewayAgentService` directly.
- Extension on `StriaEnvironment`:

  ```
  public static func liveServices(paths: StriaPaths, config: StriaConfig) -> (any OCRService, any AgentService)
  public static func live(paths: StriaPaths, config: StriaConfig, environment: [String: String] = ProcessInfo.processInfo.environment) -> StriaEnvironment
  ```

  `liveServices` reads `ProcessInfo.processInfo.environment` once and passes
  it to the gateway services.

**`Integration/RunLogWriter.swift`**

- `public struct RunLogWriter: Sendable { init(paths: StriaPaths); func
  append(_ run: AgentRunRecord) throws }`.
- Format: one JSON object plus `\n`. Keys are sorted, nulls are explicit,
  and the key set is exactly `runId, kind, docId, page, vendor, model,
  status, imageCount, startedAt, finishedAt, durationMs, error`.
- File: `paths.runLog(for: run.startedAt)`. Create `logs/` with
  permissions 0700 when it is missing.
- Write with POSIX `open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600)` and a
  single `write` of the whole line, so concurrent appends from OCR tasks do
  not interleave.
- Failures throw `ioError`. Callers decide what to do with them.

## Pitfalls

- Never put the secret value in `ServiceError` messages, logs, `PromptPart`
  or anything returned. Redact before throwing.
- Do not read `ProcessInfo` inside `GatewayPreflight`. The environment is
  injected so tests are deterministic.
- `apiKeyEnvironment` passes only the variable NAME to
  `GatewayAgentDefaults`. Never pass the value as an argument.
- One agent, connection and session per call. Do not cache them in
  properties, because concurrent OCR tasks would share a session.
- Keep agent-gateway imports confined to `Integration/` files. No other
  StriaCore folder imports them. `OCR/PDFTextLayerOCRService.swift` imports
  only Foundation and PDFKit.
- Never declare `.build/`, `.build/checkouts/agent-gateway`, `tmp/` or any
  path containing a nested `.git` in this plan's paths or in Progress Log
  requests. You may *read* `.build/checkouts/agent-gateway/Sources/...`
  after `swift package resolve`, and only when the reference doc does not
  answer a compile error. Never write there.
- Do not "fix" `cursor-api` by removing it from `KnownVendors` or config
  validation. The design keeps it as a valid config value
  (`design-agent-integration.md`, pre-call checks).
- `PDFPage.string` can be nil for image-only pages. Return `""` (a valid,
  empty `done` result), not an error.

## Tests (`Tests/StriaCoreTests/Integration/`)

No network calls.

`PreflightTests`:

- vendor "nope" -> unavailable "unknown vendor nope"
- anthropic with model nil -> unavailable
- anthropic with apiKeyEnvironment nil -> unavailable
- anthropic, ANTHROPIC_API_KEY missing from the injected env -> unavailable whose message contains "ANTHROPIC_API_KEY"
- anthropic with env {ANTHROPIC_API_KEY: "sk-test-123"} -> passes, `secretValue` "sk-test-123"
- claude-code with model nil and key nil -> passes
- cursor-api with model "m", apiKeyEnvironment "CURSOR_API_KEY" and env {CURSOR_API_KEY: "x"} -> unavailable whose message contains "cursor-api" and "image"
- claude-code with apiKeyEnvironment "FOO_KEY" and FOO_KEY missing -> unavailable naming "FOO_KEY"
- the secret value never appears in any thrown message (assert across all cases above)

`PromptPartsTests`:

- `ocrParts` order is [text, image]
- `agentParts` with 2 history turns and 2 pages -> [history text, page1 text, page1 image, page2 text, page2 image, question]
- a page without OCR text -> contains "OCR text not available"

`RedactorTests`:

- the secret appears twice -> both replaced
- a 3000-character input -> 2000 characters
- an empty secret list -> unchanged

`RunLogWriterTests`:

- append 2 runs on the same UTC day -> 2 lines in `agent-runs-YYYY-MM-DD.jsonl`
- every line parses as JSON with exactly the 12 keys, `error` null on ok
- no key contains a prompt or text field

`PDFTextLayerTests`:

- import-free setup: write a SamplePDF to `paths.original(docId:"d1")`; page 2 -> text contains the page-2 sample string
- missing doc -> `ServiceError.failed`

`LiveRoutingTests`:

- `LiveOCRService` with settings vendor `pdf-text-layer` -> returns the text layer, with no gateway call
- `LiveOCRService` with settings vendor `cursor-api` and an injected env -> `ServiceError.unavailable` from preflight; no process is launched (preflight throws before the runner)
- `StriaEnvironment.live(paths:config:environment:)` -> `paths` and `config` equal the inputs

## Verification

Run each command in the foreground with `2>&1 | tee <log>`, then record the
command, exit code and log path in the Progress Log.

- `swift build` -> exit 0 (`tmp/verify/P05/build.log`)
- `swift test --filter 'PreflightTests|PromptPartsTests|RedactorTests|RunLogWriterTests|PDFTextLayerTests|LiveRoutingTests'`
  -> all pass, 0 failures (`tmp/verify/P05/test.log`)
- `swiftlint lint Sources/StriaCore/Integration Sources/StriaCore/OCR/PDFTextLayerOCRService.swift Tests/StriaCoreTests/Integration`
  -> exit 0, 0 violations (`tmp/verify/P05/lint.log`)
- `grep -rnE '^import (AgentGateway|AgentGatewayAppCore|ACP)$' Sources | grep -v '^Sources/StriaCore/Integration/'`
  -> no output
- `grep -rn 'UnavailableOCRService\|UnavailableAgentService' Sources` -> no
  output (Mode B is dropped)
- `grep -n '\.build' impl-plans/active/stria-05-gateway-integration.md`
  -> only prose in Session-243 Revision and Pitfalls, and no entry under
  `## writePaths`, `## sharedPaths` or `## sharedPathNotes`
- `find Sources/StriaCore/Integration Sources/StriaCore/OCR/PDFTextLayerOCRService.swift Tests/StriaCoreTests/Integration -name '*.swift' -exec wc -l {} + | awk '$2 != "total" && $1 >= 1000 {bad=1; print} END {exit bad}'`
  -> exit 0

## Done Criteria

- [x] The Mode A adapters are implemented with the reference-doc API names,
  and no Mode B types exist.
- [ ] Preflight (including `cursor-api`), prompt-part ordering, redaction
  and the JSONL format are tested. Offline tests are implemented but could
  not execute because P04's test source currently fails compilation.
- [x] The live factory exists with the exact signatures.
- [x] No secret value can reach any output.
- [x] No `.build` path is declared anywhere in this plan's path declarations.

## Progress Log

- 2026-10-02 Step 6 implementation: added the Mode A gateway runner and OCR/agent adapters, ordered prompt parts, preflight, redaction, JSONL writer, PDF text-layer service, live routing/factories, and offline suites under the P05 write paths. `swift build` passed (log `tmp/stria-v01-session-243/P05-step6-intents/logs/build-final.log`). Exact changed-file SwiftLint passed (manifest `tmp/stria-v01-session-243/P05-step6-intents/changed-swift-files.nul`, log `tmp/stria-v01-session-243/P05-step6-intents/logs/swiftlint-final2.log`); Swift parse, gateway import boundary, Mode B absence, line-count, and write-path `.build` checks passed in the same evidence directory.
- Focused tests were attempted. The first attempt exposed a Swift 6.3 compiler ownership crash in `PreflightTests`; the test now asserts the exact typed error using `#expect(throws:)`. The next attempt compiled all P05 tests but stopped before test execution on the out-of-scope `Tests/StriaCoreTests/Imaging/P04ImagingTests.swift:19` throwing expression inside `#expect` (log `tmp/stria-v01-session-243/P05-step6-intents/logs/focused-tests-compiler-fix.log`, exit 1). The initial shared-tree build/test also encountered transient P03/P06 source diagnostics; the final build passes. Serial integration verification must repair/resolve P04's test compilation before rerunning the P05 suites. No agent-gateway API signature differences were found.
