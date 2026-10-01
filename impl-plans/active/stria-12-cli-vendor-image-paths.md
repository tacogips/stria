# P12 CLI Vendor Image Paths and OCR Reply Check

**Status**: In Progress
**planId**: P12
**Wave**: 1 (single plan, no dependencies)
**dependsOn**: none (builds on `main` at `8861227` plus the session-247 design update)
**Design Reference**: `design-docs/specs/design-agent-integration.md#vendor-image-capability`, `#ocr-reply-check`, `#service-boundary`, `#state-machine-per-page`, `#prompt`, `#agent-gateway-integration`; `design-docs/references/agent-gateway-c7f2697.md#image-inputs-and-process-errors`; `design-docs/user-qa/ocr-empty-reply.md`

## Purpose

Issue: page images are silently dropped for CLI agent-gateway vendors
(`claude-code`, `codex`, `cursor`) in OCR and ask.

At agent-gateway `c7f2697`, `GatewayACPAgent` moves ACP image blocks into
`GatewayExecuteParams.images`. Only the API vendors send them to the model.
`GatewayExecution.executeCLI` launches the CLI with the joined prompt text
and the working directory, and never reads `images`. As a result:

- OCR with `ocr.vendor = claude-code` stored "I don't see an image attached
  to your message..." as `ocrStatus = done`;
- ask lost its context page images in the same way.

The fix has two parts:

1. For CLI vendors, render every image part as prompt text that names the
   absolute PNG path and tells the agent to read the file. The session `cwd`
   is already `paths.cache`, which contains the PNGs. API vendors keep image
   blocks.
2. A gateway OCR reply that is empty, or that says no image was received,
   becomes `ServiceError.failed`, so the page is recorded `failed` and
   `--retry-failed` runs it again.

## Context (read before editing)

- `Sources/StriaCore/Integration/GatewayPromptRunner.swift`: `run(...)`
  - resolves `GatewayVendor(rawValue:)`, then loops over `parts`;
  - `.text` -> `ACPContentBlock.text`;
  - `.image(url)` -> `gatewayImageContentBlocks([.filePath(url.path)])`.
- `Sources/StriaCore/Integration/GatewayPromptParts.swift`
  - `enum PromptPart { case text(String); case image(URL) }`;
  - `GatewayPromptParts.ocrParts` and `agentParts`, the style to imitate.
- `Sources/StriaCore/Integration/GatewayOCRService.swift`: `recognize` calls
  the runner and returns `OCRResult(text:)`.
- `Sources/StriaCore/Integration/GatewayAgentService.swift`: ask uses the
  same runner. No change is needed here.
- `Sources/StriaCore/OCR/OCRTextPostProcessor.swift`:
  `OCRTextPostProcessor.clean(_:)` trims and strips one code fence.
- `Sources/StriaCore/OCR/OCRCoordinator.swift`: `ServiceError.failed(msg)`
  -> `recordOCRFailure` with run status `.failed`. Do not change it.
- `GatewayVendor.isCLI` is public in module `AgentGateway`
  (`.build/checkouts/agent-gateway/Sources/AgentGateway/GatewayProtocol.swift`;
  read-only, never edit). It is `true` for `.claudeCode`, `.codex` and
  `.cursor`.
- Test patterns to imitate:
  - `Tests/StriaCoreTests/Integration/PromptPartsTests.swift` (struct-based,
    `@testable import StriaCore`, `import Testing`, `#expect`);
  - `Tests/StriaCoreTests/ImportOCR/OCRCoordinatorTests.swift`:
    `withTestDataRoot`, `FakeOCRService`, `makeImportFixture`,
    `importFixture`, `library.runOCR(documentId:selection:)`,
    `library.store.pageInfo(documentId:page:)`,
    `library.store.agentRuns(documentId:)`.

## Non-goals (do not do these)

- Do not edit agent-gateway, `.build/`, `Package.swift` or
  `Package.resolved`. Do not add a dependency or a target dependency.
- Do not change these files: `OCRCoordinator`, `PDFTextLayerOCRService`,
  `OCRTextPostProcessor`, `OCRDefaults.prompt`, `GatewayPreflight` (keep the
  `cursor-api` rejection), `GatewayAgentService`, `FakeOCRService`,
  `AgentRunRecord.imageCount`, the app, the CLI, `scripts/cli-smoke.sh`.
- No reply check for ask.
- No new protocol, injection seam, config key or prompt sentinel.
- Do not edit design docs. They are already updated and accepted. If the
  design looks wrong, record it in the Progress Log.

## Deliverables and File-Level Changes

### TASK-001: Vendor-aware prompt rendering

**Parallelizable**: Yes (no shared file with TASK-002)

Files:

- `Sources/StriaCore/Integration/GatewayPromptParts.swift`
- `Sources/StriaCore/Integration/GatewayPromptRunner.swift`
- `Tests/StriaCoreTests/Integration/PromptPartsTests.swift`

Contract (internal):

```swift
static func rendered(_ parts: [PromptPart], for vendor: GatewayVendor) -> [PromptPart]
```

Add it to `enum GatewayPromptParts`, and add `import AgentGateway` to that
file.

Behavior:

- `vendor.isCLI == false`: return `parts` unchanged. This covers `openai`,
  `anthropic`, `gemini`, `openrouter` and `cursor-api`.
- `vendor.isCLI == true`: return an array of the same length. Each
  `.text(t)` stays as it is. Each `.image(url)` becomes, at the same index,
  `.text(<two lines joined with "\n">)`. The exact text (from the design):
  - line 1: `Page image file: <url.path>`
  - line 2: `Open and read this PNG file with your file-reading tool before answering. Use what it shows as the page image this request refers to.`
- Pure: no file I/O, no `FileManager`, no path rewriting. Use `url.path`
  exactly as given (it is already absolute under `paths.cache`).

Runner change:

- In `GatewayPromptRunner.run`, after `vendor` is resolved, iterate
  `GatewayPromptParts.rendered(parts, for: vendor)` instead of `parts`.
- The existing `switch` (`.text` -> text block, `.image` -> gateway image
  blocks) stays the same.
- `cwd`, the error mapping and `stopReason` handling are unchanged.

Pitfalls:

- Keep the image position. Do not move the path text to the front or merge
  it with neighboring text parts.
- Do not drop the `.image` cases from the runner switch. API vendors still
  need them.
- Use one wording for OCR and ask. Do not branch on the request kind.

### TASK-002: OCR reply check

**Parallelizable**: Yes (no shared file with TASK-001)

Files:

- New: `Sources/StriaCore/Integration/GatewayOCRReplyCheck.swift`
- `Sources/StriaCore/Integration/GatewayOCRService.swift`
- New: `Tests/StriaCoreTests/Integration/OCRReplyCheckTests.swift`

Contract (internal):

```swift
enum GatewayOCRReplyCheck {
  static let emptyReason = "OCR reply was empty; the page image may not have reached the model"
  static let noImageReason = "OCR reply says no page image was received; the agent did not read the page image"
  static func rejectionReason(for reply: String) -> String?
}
```

Algorithm (in this order):

1. `let cleaned = OCRTextPostProcessor.clean(reply)`. If `cleaned.isEmpty`,
   return `emptyReason`.
2. `let normalized = cleaned.lowercased()` with every `"\u{2019}"` replaced
   by `"'"`.
3. If `normalized.count <= 600` (Character count) and `normalized` contains
   any phrase below (plain substring match), return `noImageReason`.
4. Otherwise return `nil`.

Phrases: copy them exactly from the design section `#ocr-reply-check` into
two `static let` arrays.

- English (19): `don't see an image`, `don't see any image`, `do not see an
  image`, `do not see any image`, `no image attached`, `no image was
  attached`, `no image has been attached`, `image wasn't attached`, `image
  was not attached`, `no image was provided`, `no image provided`, `no image
  was received`, `didn't receive an image`, `did not receive an image`,
  `haven't received an image`, `have not received an image`, `can't see the
  image`, `cannot see the image`, `unable to see the image`.
- Japanese (7): `画像が添付されていません`, `画像が添付されていない`,
  `画像が見当たりません`, `画像が見当たらない`, `画像が届いていません`,
  `画像を受け取っていません`, `画像が確認できません`.

Service change (`GatewayOCRService.recognize`):

- After the runner returns `text`: if
  `GatewayOCRReplyCheck.rejectionReason(for: text)` returns a reason, throw
  `ServiceError.failed(reason)`.
- Otherwise return `OCRResult(text: text)` with the raw text. Do not return
  the cleaned text; the coordinator cleans it.

Pitfalls:

- The reason strings are fixed. Never append or quote the reply, because run
  records must not contain OCR text.
- Do not add a bare `no image` phrase (false positives).
- Do not put the check in `OCRCoordinator`. It would then apply to
  `pdf-text-layer`, and blank text-layer pages must stay `done`.

## Test Cases

`Tests/StriaCoreTests/Integration/PromptPartsTests.swift` (add
`import AgentGateway`; keep the two existing tests unchanged):

- `ocrParts` (pngPath `/tmp/page.png`) rendered for each of `.claudeCode`,
  `.codex` and `.cursor`:
  - no `.image` part;
  - same count as the input;
  - index 0 is the unchanged prompt text;
  - index 1 is `.text` equal to
    `"Page image file: /tmp/page.png\nOpen and read this PNG file with your file-reading tool before answering. Use what it shows as the page image this request refers to."`
- `agentParts` with two context pages (`/tmp/1.png`, `/tmp/2.png`) and
  history, rendered for each CLI vendor:
  - no `.image` part;
  - the parts at the original image indices are `.text` containing
    `Page image file: /tmp/1.png` and `Page image file: /tmp/2.png`
    respectively, plus `Open and read this PNG file`;
  - every other part equals the input.
- The same `ocrParts` and `agentParts` rendered for each of `.openAI`,
  `.anthropic`, `.gemini` and `.openRouter`: the output equals the input
  (`.image` parts kept).

`Tests/StriaCoreTests/Integration/OCRReplyCheckTests.swift` (new;
`import Foundation`, `@testable import StriaCore`, `import Testing`):

- `""` -> `emptyReason`
- `"  \n\t "` -> `emptyReason`
- `` "```\n```" `` -> `emptyReason`
- `"I don\u{2019}t see an image attached to your message, so there's nothing for me to transcribe."` -> `noImageReason` (the issue's repro, with a curly apostrophe)
- `"I DO NOT SEE ANY IMAGE in your message."` -> `noImageReason` (case-insensitive)
- `"画像が添付されていません。もう一度送ってください。"` -> `noImageReason`
- `"画像が見当たりません"` -> `noImageReason`
- `"Chapter 1\nIntroduction\n第1章 はじめに"` -> `nil`
- A reply longer than 600 characters that contains `no image attached`
  (for example the phrase plus `String(repeating: "page text ", count: 80)`)
  -> `nil`
- Coordinator integration, offline:
  - setup: `withTestDataRoot`, `FakeOCRService`,
    `makeImportFixture(pageTexts: ["a"])`, `importFixture`;
  - `let reason = GatewayOCRReplyCheck.rejectionReason(for: "I don't see an image attached.")!`;
  - `fake.setDefault(.failure(.failed(reason)))`;
  - `runOCR(selection: .pending)`;
  - expect: `failed == 1` and `done == 0`; page 1 `ocrStatus == .failed`;
    `ocrError == reason`; `agentRuns(documentId:)` has exactly one row,
    with `status == .failed`.

## Invariants (must remain true)

- API vendor prompts are byte-for-byte the same as before (same parts, same
  order, image blocks).
- `cwd` stays `paths.cache` for every vendor.
- `pdf-text-layer` empty pages stay `done`. `scripts/cli-smoke.sh` behavior
  is unchanged.
- `cursor-api` is still rejected by preflight as `unavailable`.
- No network call or vendor process in any test.
- Every Swift file stays under 1000 lines. `swiftlint` reports 0
  violations.

## Execution Protocol

- Follow `AGENTS.md`: English only, no emojis, use
  `.codex/skills/swift-coding-agent/SKILL.md`, run `swiftlint` after Swift
  edits.
- Re-read each file immediately before editing it.
- Record `shasum -a 256 <file>` (or `absent`) before the first edit and
  after the last edit in the Progress Log. Re-hash all six files before
  final verification. On drift, re-read, re-apply only this plan's intent,
  and log the drift.
- Edit only the `writePaths` below. Of this plan file, edit only
  `## Progress Log`.
- No git state changes (no add, commit, stash, checkout, reset, branch or
  worktree). Read-only `git status` and `git diff` are fine.
- Run every verification in the foreground with `set -o pipefail` and `tee`
  it to `tmp/stria-session-247/P12/<name>.log`. `tmp/` is evidence output
  only and is not a plan path.
- Final verification records use the numeric form
  `{"command": ..., "exitCode": N, ...}`. Do not list intentional red-phase
  runs in the final list.

## Verification Commands

| # | Command (run from repo root, `set -o pipefail`) | Required evidence |
| --- | --- | --- |
| V1 | `swift build 2>&1 \| tee tmp/stria-session-247/P12/build.log` | exitCode 0 |
| V2 | `swift test --filter 'PromptPartsTests\|OCRReplyCheckTests' 2>&1 \| tee tmp/stria-session-247/P12/test-focused.log` | exitCode 0; every new test listed as passed |
| V3 | `swift test 2>&1 \| tee tmp/stria-session-247/P12/test-all.log` | exitCode 0; record testsRun, testsPassed, failureCount 0 (the baseline was 120 tests, so testsRun must be above 120) |
| V4 | `swiftlint 2>&1 \| tee tmp/stria-session-247/P12/swiftlint.log` | exitCode 0; `Found 0 violations` |
| V5 | `bash scripts/cli-smoke.sh 2>&1 \| tee tmp/stria-session-247/P12/cli-smoke.log` | exitCode 0; log contains `SMOKE OK` |
| V6 | `find Sources Tests -name '*.swift' -exec wc -l {} + \| awk '$2 != "total" && $1 >= 1000'` | exitCode 0 and empty output |
| V7 | `git status --porcelain=v1 --untracked-files=all` | changed paths are only this plan's `writePaths` (plus ignored `tmp/` logs) |

## Write Paths

- `Sources/StriaCore/Integration/GatewayPromptParts.swift`
- `Sources/StriaCore/Integration/GatewayPromptRunner.swift`
- `Sources/StriaCore/Integration/GatewayOCRReplyCheck.swift` (new)
- `Sources/StriaCore/Integration/GatewayOCRService.swift`
- `Tests/StriaCoreTests/Integration/PromptPartsTests.swift`
- `Tests/StriaCoreTests/Integration/OCRReplyCheckTests.swift` (new)
- `impl-plans/active/stria-12-cli-vendor-image-paths.md` (Progress Log only)

Shared (read-only): `design-docs/specs/design-agent-integration.md`,
`design-docs/references/agent-gateway-c7f2697.md`,
`Sources/StriaCore/OCR/OCRTextPostProcessor.swift`,
`Sources/StriaCore/OCR/OCRCoordinator.swift`,
`Tests/StriaCoreTests/Support/FakeOCRService.swift`,
`Tests/StriaCoreTests/ImportOCR/ImportOCRTestSupport.swift`,
`scripts/cli-smoke.sh`.

## Completion Criteria

- [ ] `GatewayPromptParts.rendered(_:for:)` exists with the pinned signature
      and text template. `GatewayPromptRunner.run` iterates its output.
- [ ] `GatewayOCRReplyCheck` exists with the pinned reasons, the phrase
      lists and the 600-character limit. `GatewayOCRService.recognize` throws
      `ServiceError.failed(reason)` on rejection.
- [ ] All test cases above exist and pass (V2).
- [ ] V1-V7 meet their required evidence, recorded with numeric exitCode.
- [ ] No file outside the write paths changed (V7).
- [ ] Progress Log has pre- and post-hashes, verification records and any
      drift notes.

## Progress Log

- 2026-10-02: Plan created (session 247, Step 4).
