# OCR, Agent Q&A, agent-gateway Integration, Config

## Status

Draft (stria v0.1). riela is not used: `../user-qa/no-riela-decision.md`.

## Service Boundary

All model calls go through two `StriaCore` protocols. Everything above them
(import, OCR coordinator, ask, CLI, app) does not depend on the integration
and is tested with fakes.

```
protocol OCRService: Sendable {
  func recognize(_ request: OCRRequest) async throws -> OCRResult
}
OCRRequest  { docId, page, pngPath, prompt, settings: ServiceSettings }
OCRResult   { text }

protocol AgentService: Sendable {
  func ask(_ request: AgentRequest) async throws -> AgentAnswer
}
AgentRequest { question, systemPrompt, contextPages: [ContextPage],
               history: [ChatTurn], settings: ServiceSettings }
ContextPage  { docId, title, page, ocrText?, pngPath }
ChatTurn     { role, content }
AgentAnswer  { text }

ServiceSettings { vendor, model?, apiKeyEnvironment? }   // from config
```

Implementations:

| Type | Used when |
| --- | --- |
| `GatewayOCRService`, `GatewayAgentService` | Production. Call agent-gateway in-process (below) |
| `PDFTextLayerOCRService` | `ocr.vendor = "pdf-text-layer"` (below) |
| `FakeOCRService`, `FakeAgentService` | Tests only (test target). Scripted results and errors, recorded requests |

Services throw `ServiceError`, which the coordinators handle as follows:

- `unavailable(reason)`: a configuration problem, such as an unknown vendor,
  a missing model for an API vendor, `apiKeyEnvironment` unset or the named
  variable missing, or the agent-gateway executable not found. It is detected
  before any page is touched or any message is persisted. OCR: the run aborts
  and pages stay `pending`. Ask: nothing is persisted. CLI exit 4.
- `failed(message)`: the call itself failed (transport, vendor error, or a
  stop reason other than end of turn). OCR: that page becomes `failed`. Ask:
  the failure is persisted as an assistant `error` message. CLI exit 5.

Answers are aggregated in v0.1. There is no token streaming.

## Run Records

The coordinators (not the services) wrap every `recognize` and `ask` call:

1. Generate `runId` (UUID) and record the start time.
2. Call the service.
3. Write one `agent_runs` row (`design-storage.md#schema-v1`) in the same
   transaction as the page result or the chat messages.
4. After commit, append one JSON line to
   `<root>/logs/agent-runs-YYYY-MM-DD.jsonl` (UTC date):
   `{runId, kind, docId, page, vendor, model, status, imageCount, startedAt,
   finishedAt, durationMs, error}`.

Because the coordinators do the recording, runs made with fakes are recorded
too, and tests assert them. `unavailable` produces no run, because no call is
attempted. The JSONL append is best effort: a failure is reported once on
stderr by the CLI (silently skipped in the app) and never fails the
operation. The DB row is authoritative. Run records never contain prompts,
OCR text, answers, images or credential values.

## OCR

### Selection

| Invocation | Pages processed |
| --- | --- |
| import (no `--no-ocr`) / app auto-OCR after import | `pending` |
| `stria ocr <docId>` / app "Run OCR" | `pending` |
| `--retry-failed` / app "Retry Failed OCR" | `pending` + `failed` |
| `--pages 1,3-5` | exactly those pages, any status (explicit re-run) |

### State machine (per page)

```
pending --ok--> done        (text, vendor, model stored; FTS row replaced; error cleared)
pending --err-> failed      (ocr_error stored redacted, ocr_attempts += 1)
failed  --ok--> done        (only when selected via --retry-failed or --pages)
failed  --err-> failed
done    --ok/err--> done/failed   (only via --pages)
any     --unavailable--> unchanged (run aborted before the first call)
```

Each page gets one attempt per run. A retry is an explicit later run. Text
post-processing: trim the text, and strip one surrounding Markdown code fence
if the model added one. An empty result is a valid `done` with empty text.

### Execution

- A bounded `TaskGroup` with width `ocr.concurrency` (default 2, clamped to
  1...8).
- Per page: `PageImageCache.expand`, then `OCRService.recognize` with the PNG
  path and `ocr.prompt` (default below), then store the result and the run
  record.
- Progress events are sent through `AsyncStream`. Cancellation stops
  scheduling new pages and leaves unfinished pages `pending`.
- The run summary is
  `{ processed, done, failed, pending, failures: [{page, error}] }`.

Default OCR prompt:

> Transcribe all text visible in this page image. The text may be Japanese,
> English or both. Preserve reading order and line breaks. Output only the
> transcribed text with no commentary, headings or code fences. If the page
> has no text, output nothing.

### `pdf-text-layer` local service

`ocr.vendor = "pdf-text-layer"` is a reserved vendor implemented in
`StriaCore` without agent-gateway. It returns `PDFPage.string` from the
original PDF.

It exists so the real `stria` binary can fill in OCR text offline during the
CLI smoke run (the "test hook" in the acceptance criteria), and it is usable
for PDFs that already have a text layer. It is never the default, and it is
not an AI path, so agent-gateway remains the only AI library.

## Ask

### Context selection

| Caller | Context pages |
| --- | --- |
| App scope "This page" | current page |
| App scope "Nearby pages" | current page +/- `agent.neighborPages` (default 1), clamped to the document |
| App scope "Whole PDF" | top `agent.maxImages` pages from fuzzy retrieval within the document; the current page is always included |
| CLI `--doc D --page N` | page N of D |
| CLI `--doc D` | fuzzy retrieval within D |
| CLI (no `--doc`) | fuzzy retrieval across all documents |

- Fuzzy retrieval is defined in `design-storage.md#fuzzy-retrieval-ask`.
  `--query <terms>` replaces the question as the retrieval input.
- At most `agent.maxImages` pages are sent (default 4).
- For each page, stria sends the expanded PNG (always) and the OCR text (when
  `done`). OCR text is truncated so the total stays within
  `agent.maxContextCharacters` (default 60000).
- If retrieval returns no page, `ask` fails with `noRelevantPages` (exit 3),
  calls no model and persists nothing.

### Prompt

The system prompt can be overridden with `agent.systemPrompt`. It tells the
model to:

- answer from the supplied pages;
- say when the pages do not contain the answer;
- cite pages as `[<docId> p.<page>]`.

The user prompt is a sequence of content blocks:

1. If the thread has earlier turns, a text block "Previous conversation:"
   with those turns. The app sends the active thread's turns; each CLI `ask`
   starts a new thread.
2. For each context page, a text block `Document "<title>" (<docId>) page
   <page>` followed by the OCR text (or "OCR text not available"), then the
   page's image block.
3. A text block with the question.

### Persistence

One transaction after the call returns:

1. Ensure the thread exists. Its scope is the app scope (`page`, `nearby`,
   `document`). For the CLI the scope is `page` with `--doc --page`,
   `document` with `--doc`, and `library` otherwise.
2. Write the `agent_runs` row first, because `chat_messages.agent_run_id`
   references it and foreign keys are enforced immediately.
3. Insert the user message. Its `document_id` / `page_number` is the anchor
   page: the app's current page, the CLI `--doc` / `--page`, or null.
4. Insert the assistant message: `ok` with the answer, or `error` with the
   redacted error text. It carries the same anchor `document_id` /
   `page_number` as the user message, so every question and answer appears
   in per-page and per-PDF history.
5. On the assistant message, set `citations_json` to the context pages sent,
   plus vendor, model and `agent_run_id`.

A `failed` call is still persisted, so history reflects every question that
was sent to a model. An `unavailable` error (no call attempted) and
`noRelevantPages` persist nothing.

## agent-gateway Integration

Dependency: `.package(url: "https://github.com/tacogips/agent-gateway.git",
revision: "c7f269753ec36aca92d429ec13316ba033128967")`, using the products
`AgentGateway`, `AgentGatewayAppCore` and `ACP`. That revision is the remote
`main` HEAD confirmed at intake. The agent-gateway repository is never
modified, and no local-path dependency is added.

The API at that revision, as stated in the intake, is used only inside
`StriaCore/Integration/`:

1. `GatewayAgentDefaults(vendor:model:systemPrompt:executable:arguments:
   providerName:apiKeyEnvironment:baseURL:maxTokens:cursorAPI:)` is built from
   `ServiceSettings`:
   - `vendor` comes from `GatewayVendor(rawValue: settings.vendor)`;
   - `model` and `apiKeyEnvironment` are passed through;
   - `systemPrompt` is the ask system prompt (nil for OCR);
   - all other parameters use their defaults.
2. `GatewayACPAgent(defaults:executor: ProductionGatewayExecutor(environment:
   ProcessInfo.processInfo.environment))`.
3. `ACPClientConnection.inProcess(agent:)` returns `(client, server)`.
4. `client.initialize()`, then
   `client.newSession(ACPNewSessionRequest(cwd: <root>/cache))`.
5. `client.promptCollecting(ACPPromptRequest(sessionId:prompt:))`. The prompt
   is text blocks plus `gatewayImageContentBlocks([.filePath(<absolute PNG
   path>)])` for each image.
6. On success, the result's `messageText` is the answer. A
   `response.stopReason` other than end of turn is `failed("stop reason:
   <reason>")`. A thrown error is `failed(<redacted message>)`.

Each call creates its own agent, connection and session. Sessions are never
reused, so concurrent OCR pages cannot cross-talk. The session `cwd` is the
data root's `cache/` directory, which already contains the PNGs. stria writes
nothing else there.

Pre-call checks, which produce `unavailable` and make no call:

- the vendor is not a `GatewayVendor` raw value;
- the vendor is an API vendor (`openai`, `anthropic`, `gemini`, `openrouter`,
  `cursor-api`) and `model` or `apiKeyEnvironment` is null;
- the named environment variable is unset or empty;
- the vendor is `cursor-api`. At the pinned revision `cursor-api` rejects
  gateway image inputs, and every OCR and ask call sends at least one image
  (`../references/agent-gateway-c7f2697.md`). Config still accepts the value,
  so the error names the reason instead of failing config validation.

CLI-backed vendors (`claude-code`, `codex`, `cursor`) use their own login,
may leave `apiKeyEnvironment` null, and fail with `unavailable` when the
gateway reports that the executable cannot be launched
(`GatewayProcessError.launchFailed`).

Implementation gate G1 (API confirmation) is done. The signatures, the
`GatewayVendor` raw values, the `ACPStopReason` enum (`endTurn` is success)
and the per-vendor image support are recorded in
`../references/agent-gateway-c7f2697.md`. That file is the API source of truth
for implementers. `gatewayImageContentBlocks([.filePath(...)])` converts files
to inline base64 blocks itself, so the adapter always passes `.filePath`.

If the adapter fails to compile against the pinned revision, the implementer
may read `.build/checkouts/agent-gateway` after `swift package resolve`, but
only read-only. That checkout is SwiftPM build output with a nested `.git`, so
no plan or dispatch manifest may declare it (or anything under `.build/`) in
`writePaths`, `sharedPaths` or `trackedPaths`
(`architecture.md#implementation-rollout`). Signature differences are
absorbed inside `Integration/` only, and the reference file is updated to
match. If the package cannot be resolved or built, that is a blocker reported
with the command, exit code and log path. In that case
`StriaEnvironment.live` falls back to services that throw
`unavailable("agent-gateway integration unavailable: ...")`, so import,
`--no-ocr`, `pdf-text-layer`, search, page image, history and the reader
still work. No local-path dependency is added without user approval.

## Config

`<root>/config.json` is created with defaults on first run (atomic write) and
is never rewritten on load:

- missing keys take their defaults;
- unknown keys are ignored;
- invalid JSON or out-of-range values fail with `configInvalid` and leave the
  file untouched.

```json
{
  "version": 1,
  "render": { "dpi": 150, "imageFormat": "heic", "quality": 0.75, "maxPixelDimension": 4096 },
  "ocr": {
    "vendor": "anthropic", "model": "claude-sonnet-5-5",
    "apiKeyEnvironment": "ANTHROPIC_API_KEY", "concurrency": 2, "prompt": null
  },
  "agent": {
    "vendor": "anthropic", "model": "claude-opus-5-5",
    "apiKeyEnvironment": "ANTHROPIC_API_KEY", "neighborPages": 1,
    "maxImages": 4, "maxContextCharacters": 60000, "systemPrompt": null
  }
}
```

Validation for `stria config set <key> <value>` (dotted keys above):

| Key | Valid values |
| --- | --- |
| `render.dpi` | 72...600 |
| `render.quality` | 0.1...1.0 |
| `render.imageFormat` | `heic` or `jpeg` |
| `render.maxPixelDimension` | 1024...8192 |
| `ocr.concurrency` | 1...8 |
| `agent.neighborPages` | 0...5 |
| `agent.maxImages` | 1...10 |
| `agent.maxContextCharacters` | 1000...500000 |
| `ocr.vendor`, `agent.vendor` | a `GatewayVendor` raw value (`claude-code`, `codex`, `cursor`, `cursor-api`, `openai`, `anthropic`, `gemini`, `openrouter`); `ocr.vendor` also accepts `pdf-text-layer` |
| `ocr.apiKeyEnvironment`, `agent.apiKeyEnvironment` | must match `^[A-Z_][A-Z0-9_]*$`, or `null` |

The value `null` clears the optional keys `model`, `apiKeyEnvironment`,
`prompt` and `systemPrompt`. The default values are recorded in
`../user-qa/default-agent-config.md`.

## Secrets

- Config, DB, run logs and JSON output contain environment variable names
  only, never their values.
- stria reads `ProcessInfo.processInfo.environment[name]` only to check that
  the variable is present and to redact its value. agent-gateway receives the
  environment through `ProductionGatewayExecutor(environment:)` and the
  variable name through `apiKeyEnvironment`. stria never passes the value as
  an argument and never logs it.
- Before any service error is persisted or printed, the resolved secret value
  (if any) is replaced with `[REDACTED]` and the text is truncated to 2000
  characters.
- The `apiKeyEnvironment` name pattern rejects most pasted keys (lowercase
  letters, dashes), which prevents a secret from being stored by accident.
- An app launched from Finder does not inherit shell variables. The agent
  pane and the library row show the `unavailable` reason, naming the variable.
