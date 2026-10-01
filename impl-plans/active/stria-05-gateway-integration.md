# P05 agent-gateway Adapters, Live Services, pdf-text-layer, Redaction, Run Log Writer

**Status**: Ready
**planId**: P05
**Wave**: 2
**dependsOn**: P01
**Design Reference**: `design-docs/specs/design-agent-integration.md#service-boundary`, `#run-records`, `#pdf-text-layer-local-service`, `#prompt`, `#agent-gateway-integration`, `#secrets`; `design-docs/references/agent-gateway-c7f2697.md` (written by P01, authoritative for signatures)

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

**Mode selection.** If the P01 reference doc starts with "G1 FAILED", use
Mode B: do not import agent-gateway modules, and make the live services
return `UnavailableOCRService` / `UnavailableAgentService`, which throw
`ServiceError.unavailable("agent-gateway integration unavailable: <reason from doc>")`.
`pdf-text-layer` routing still works in Mode B. Otherwise use Mode A (the
normal case).

## Non-goals

- No coordinators: no page state, chat persistence or agent_runs rows (P07
  and P08 own those).
- No streaming, no per-call timeout, no session reuse.
- No riela.
- Do not modify `Package.swift`.

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
- `.build/checkouts/agent-gateway`

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
- `{path: ".build/checkouts/agent-gateway", intendedEdit: "read-only source reference produced by swift package resolve"}`

## Files and Contracts

**`Integration/SecretRedactor.swift`**

- `public enum SecretRedactor`.
- `static func redact(_ text: String, secrets: [String]) -> String`:
  replaces each non-empty secret with `[REDACTED]`, then truncates.
- `static func truncate(_ text: String, limit: Int = 2000) -> String`:
  cuts at a Character boundary.

**`Integration/GatewayPreflight.swift`**

- `struct PreflightResult { vendor: <GatewayVendor in Mode A, String in Mode B>, secretValue: String? }`.
- `static func check(_ settings: ServiceSettings, environment: [String: String]) throws(ServiceError) -> PreflightResult`
  throws `unavailable` with a message naming the problem when:
  - the vendor is not a `GatewayVendor` raw value: "unknown vendor <v>";
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

**`Integration/GatewayPromptRunner.swift`** (Mode A only; not unit-tested)

- `func run(settings:systemPrompt:parts:cwd:environment:) async throws ->
  String`, following `design-agent-integration.md#agent-gateway-integration`
  steps 1-6:
  1. build the defaults: `GatewayAgentDefaults(vendor:model:systemPrompt:apiKeyEnvironment:...)`,
     with the remaining parameters at their defaults;
  2. `GatewayACPAgent(defaults:executor: ProductionGatewayExecutor(environment:))`;
  3. `ACPClientConnection.inProcess(agent:)`;
  4. `initialize`, then `newSession(cwd: paths.cache path)`;
  5. `promptCollecting` with the text blocks plus
     `gatewayImageContentBlocks([.filePath(url.path)])`. Use
     `.data(mimeType: "image/png", base64:)` for vendors the reference doc
     says ignore `.filePath`;
  6. a stop reason other than end of turn becomes
     `ServiceError.failed("stop reason: <r>")`.
- Map errors:
  - the reference doc's executable-launch error (if one exists) becomes
    `unavailable("vendor executable could not be launched: <redacted>")`;
  - any other thrown error becomes `failed(SecretRedactor.redact(String(describing: error), secrets: [secretValue]))`.
- Use the exact API names from the reference doc. If they differ from the
  design's names, follow the reference doc and note the difference in the
  Progress Log.

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

- `struct LiveOCRService: OCRService`: routes to `PDFTextLayerOCRService`
  when `request.settings.vendor == KnownVendors.pdfTextLayer`, otherwise to
  `GatewayOCRService` (or the unavailable service in Mode B). Routing is per
  request, so a config change takes effect without a rebuild.
- `UnavailableOCRService` and `UnavailableAgentService` (both modes; used
  in Mode B).
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
  StriaCore folder imports them.

## Tests (`Tests/StriaCoreTests/Integration/`)

No network calls.

`PreflightTests`:

- vendor "nope" -> unavailable "unknown vendor nope"
- anthropic with model nil -> unavailable
- anthropic with apiKeyEnvironment nil -> unavailable
- anthropic, ANTHROPIC_API_KEY missing from the injected env -> unavailable whose message contains "ANTHROPIC_API_KEY"
- anthropic with env {ANTHROPIC_API_KEY: "sk-test-123"} -> passes, `secretValue` "sk-test-123"
- claude-code with model nil and key nil -> passes

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
- in Mode B, a gateway vendor -> unavailable

## Verification

- `swift build` -> exit 0 (`tmp/verify/P05/build.log`)
- `swift test --filter` for the suites above -> pass (`tmp/verify/P05/test.log`)
- `swiftlint lint Sources/StriaCore/Integration Sources/StriaCore/OCR/PDFTextLayerOCRService.swift Tests/StriaCoreTests/Integration`
  -> exit 0
- `grep -rn "import AgentGateway\|import ACP\|import AgentGatewayAppCore" Sources | grep -v "Sources/StriaCore/Integration/"`
  -> no output

## Done Criteria

- [ ] Mode A (or the documented Mode B) is implemented.
- [ ] Preflight, prompt-part ordering, redaction and the JSONL format are
  tested.
- [ ] The live factory exists with the exact signatures.
- [ ] No secret value can reach any output.

## Progress Log

- (worker appends entries here)
