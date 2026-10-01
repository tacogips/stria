# P06 CLI Argument Parser, Usage, JSON Output Helpers, Config Key Get/Set

**Status**: Ready (re-issued in session 243)
**planId**: P06
**Wave**: 1 of the session-243 manifest
**dependsOn**: none in this manifest (builds on completed P01, commit `2ea8582`)
**Design Reference**: `design-docs/specs/command.md#global-rules`, `#commands`; `design-docs/specs/design-agent-integration.md#config` (validation table); `design-docs/specs/architecture.md#implementation-rollout`

## Session-243 Revision

The tasks, contracts and paths are unchanged from session 241. Checked
against the wave-1 code:

- `Sources/StriaCore/Config/StriaConfig.swift:StriaConfig.validate()` is
  `throws(StriaError)` and throws `configInvalid` (`.config(_:)`), so the
  `configInvalid -> usageError` mapping below is valid;
- `KnownVendors.gateway` already includes `cursor-api`, and
  `KnownVendors.pdfTextLayer` is `pdf-text-layer`;
- `StriaConfig` has exactly 16 leaf keys (render 4, ocr 5, agent 7);
- `Models/StriaDateFormat.swift:StriaDateFormat.string(from:)` is the date
  encoder to use;
- `Version.swift:Version.current` is `"0.1.0"`.

`config set ocr.vendor cursor-api` stays valid (exit 0). The `cursor-api`
image limitation is enforced by P05's preflight, not by this plan.

## Intent and Context

The CLI extends the scaffold's hand-written parsing style (the deleted
`KaibaViewerCommand.run` scanned `arguments`) instead of adding
swift-argument-parser. This plan provides:

- the pure parser that turns `[String]` into a typed invocation;
- the usage text;
- the JSON encoder and error envelope;
- config key-path get/set with validation.

P09 wires these to the library in wave 4.

## Non-goals

- No command execution, no DB access and no file IO.
- No new dependencies.

## writePaths

- `Sources/StriaCore/CLI/ParsedInvocation.swift`
- `Sources/StriaCore/CLI/CommandLineParser.swift`
- `Sources/StriaCore/CLI/PageListParser.swift`
- `Sources/StriaCore/CLI/Usage.swift`
- `Sources/StriaCore/CLI/CLIJSON.swift`
- `Sources/StriaCore/Config/ConfigKeyPath.swift`
- `Tests/StriaCoreTests/CLIParsing`
- `impl-plans/active/stria-06-cli-parser-config-keys.md`

## sharedPaths

- `Sources/StriaCore/Errors/StriaError.swift`
- `Sources/StriaCore/Config/StriaConfig.swift`
- `Sources/StriaCore/Config/ConfigStore.swift`
- `Sources/StriaCore/Version.swift`

## sharedPathNotes

- `{path: "Tests/StriaCoreTests/CLIParsing", intendedEdit: "directory"}`
- `{path: "impl-plans/active/stria-06-cli-parser-config-keys.md", intendedEdit: "append to the Progress Log section only"}`
- `{path: "Sources/StriaCore/Errors/StriaError.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Config/StriaConfig.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Config/ConfigStore.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Version.swift", intendedEdit: "read-only"}`

## Contracts

**`ParsedInvocation.swift`**

```
public struct ParsedInvocation: Equatable, Sendable { public let home: String?; public let command: CLICommand }
public enum CLICommand: Equatable, Sendable {
  case help(topic: String?), version
  case importPDF(path: String, noOCR: Bool)
  case ocr(docId: String, pages: String?, retryFailed: Bool)
  case list, show(docId: String)
  case pageImage(docId: String, page: Int, output: String?)
  case pageText(docId: String, page: Int)
  case search(query: String, docId: String?, limit: Int?)
  case ask(question: String, docId: String?, page: Int?, query: String?, limit: Int?)
  case history(docId: String?, page: Int?, limit: Int?)
  case configGet(key: String?), configSet(key: String, value: String)
  case paths
}
```

**`CommandLineParser.parse(_ arguments: [String]) throws(StriaError) -> ParsedInvocation`**

Rules (all errors are `usageError` with a specific message):

- Global options:
  - `--home <path>` may appear anywhere, but only once; a missing value is
    an error;
  - `--json` may appear anywhere and is ignored;
  - `--help` or `-h` anywhere gives `.help(topic: <first command word or nil>)`;
  - `--version` gives `.version`;
  - no arguments gives `.help(topic: nil)`.
- Command words:
  - `import`, `ocr`, `list`, `show`, `search`, `ask`, `history` and `paths`
    are single words;
  - `page` takes the subcommands `image` and `text`;
  - `config` takes `get` and `set`. Bare `config` is `configGet(key: nil)`.
- Options per command:
  - `import`: `--no-ocr`
  - `ocr`: `--pages <list>`, `--retry-failed`
  - `page image`: `--output <path>`
  - `search`: `--doc`, `--limit`
  - `ask`: `--doc`, `--page`, `--query`, `--limit`
  - `history`: `--doc`, `--page`, `--limit`
  - An option not listed for the command is an error, for example
    "unknown option --foo for search".
- Positionals:
  - exact counts per command; extra or missing positionals are errors;
  - `ask` and `search` take exactly one positional, so multi-word text must
    be quoted by the caller;
  - `config set` takes exactly 2 (key, value).
- Integers (`page`, `--page`, `--limit`): a decimal integer of 1 or more,
  otherwise an error.
- `--page` without `--doc` (ask, history) is an error.
- Range checks that need config or a document (search limit 1...100, ask
  limit, page within page count) are not done here. P03 and P09 do them.
- `--pages` is passed through as a string. P09 parses it with
  `PageListParser` once the page count is known.
- An option that takes a value may not take a value starting with `--`
  (`--doc --limit` is an error).

**`PageListParser.parse(_ text: String, pageCount: Int) throws(StriaError) -> [Int]`**

- Accepts `"1,3-5"`. Returns pages sorted and unique.
- Errors: an empty element, a reversed range, 0, or a page above
  `pageCount` (`usageError` naming the token).

**`Usage.swift`**

- `public enum Usage { static let general: String; static func text(for
  topic: String?) -> String }`.
- Plain-text usage listing every command signature exactly as in
  `command.md`, plus the global options. An unknown topic returns the
  general text.

**`CLIJSON.swift`**

```
public struct CommandOutput: Equatable, Sendable { public var stdout: String; public var stderr: String; public var exitCode: Int32 }
public enum CLIJSON {
  public static func makeEncoder() -> JSONEncoder   // .sortedKeys, .withoutEscapingSlashes; dates as StriaDateFormat strings
  public static func success<T: Encodable>(_ value: T) throws -> CommandOutput   // stdout = json + "\n", stderr "", exit 0
  public static func failure(_ error: StriaError) -> CommandOutput   // stdout "", stderr {"error":{"code":..,"message":..}} + "\n", exit error.exitCode
}
```

- `public enum JSONValue: Codable, Equatable, Sendable { null, bool, int,
  double, string, array, object }`, used by `config get` and by P09 when a
  dynamic shape is needed.
- Date strategy: `.custom`, encoding with `StriaDateFormat.string`.

**`ConfigKeyPath.swift`**

- `public enum ConfigKeyPath`.
- `static let keys: [String]`: every dotted leaf key, for example
  `render.dpi`, `ocr.vendor` and `agent.systemPrompt`, but not `version`.
- `static func value(of key: String, in config: StriaConfig)
  throws(StriaError) -> JSONValue`: an unknown key is `usageError`.
- `static func setting(_ key: String, to raw: String, in config:
  StriaConfig) throws(StriaError) -> StriaConfig`, which parses `raw` by key
  type:
  - Int keys need an integer;
  - Double keys need a number;
  - `render.imageFormat` needs `heic` or `jpeg`;
  - String keys take `raw` as-is;
  - the literal `null` clears the nullable keys `*.model`,
    `*.apiKeyEnvironment`, `ocr.prompt` and `agent.systemPrompt`. On any
    other key, `null` is `usageError`.
  Then call `config.validate()` and map `configInvalid` to `usageError`
  with the same message (design: invalid values on `set` exit 2). Return the
  new config. Saving is done by P09 through `ConfigStore.save`.

## Pitfalls

- Do not use `encodeIfPresent` for optional output fields. `JSONValue.null`
  must encode as `null`.
- Keys must be sorted (`.sortedKeys`), and slashes must not be escaped
  (paths are printed).
- The parser must be pure: no `ProcessInfo`, no `FileManager`.
- Do not call `exit()` anywhere in StriaCore.

## Tests (`Tests/StriaCoreTests/CLIParsing/`)

`ParserTests`:

- `["--home","/tmp/x","list"]` and `["list","--home","/tmp/x"]` -> home "/tmp/x", `.list`
- `["import","a.pdf","--no-ocr","--json"]` -> `.importPDF("a.pdf", true)`
- `["page","image","abc","3","--output","/tmp/o.png"]` -> `.pageImage`
- `["page","text","abc","0"]` -> usageError
- `["search","foo","--doc","d","--limit","5"]` -> `.search`
- `["search"]` -> usageError
- `["search","a","b"]` -> usageError
- `["ask","q","--page","2"]` -> usageError (page without doc)
- `["history","--doc","d","--page","2"]` -> `.history`
- `["config"]` -> `.configGet(nil)`
- `["config","set","ocr.concurrency","4"]` -> `.configSet`
- `["list","--foo"]` -> usageError
- `[]` -> `.help(nil)`
- `["search","--help"]` -> `.help("search")`
- `["--version"]` -> `.version`
- `["--home"]` -> usageError
- `["ocr","d","--pages","1,3-5","--retry-failed"]` -> `.ocr`

`PageListTests`:

- "1,3-5" with count 5 -> [1,3,4,5]
- "3,1,1" -> [1,3]
- "5-3" -> error
- "0" -> error
- "6" with count 5 -> error
- "1,,2" -> error

`CLIJSONTests`:

- `success` of a struct with a nil optional encoded through `JSONValue` -> contains `null`
- key order is sorted
- "/a/b" is not escaped
- `failure(usageError)` -> stdout empty, stderr parses to `{error:{code:"usageError",message}}`, exit 2

`ConfigKeyPathTests`:

- `keys` contains exactly the 16 leaf keys of the design config example (render 4, ocr 5, agent 7)
- get `ocr.model` -> `.string`
- set `ocr.concurrency` "4" -> 4
- set `ocr.concurrency` "9" -> usageError
- set `render.imageFormat` "png" -> usageError
- set `agent.model` "null" -> nil
- set `render.dpi` "null" -> usageError
- set `ocr.apiKeyEnvironment` "sk-live-abc" -> usageError
- set `ocr.vendor` "pdf-text-layer" -> ok
- set `agent.vendor` "pdf-text-layer" -> usageError
- unknown key -> usageError

## Verification

- `swift build` -> exit 0 (`tmp/verify/P06/build.log`)
- `swift test --filter` for the suites above -> pass (`tmp/verify/P06/test.log`)
- `swiftlint lint` on this plan's files -> exit 0

## Done Criteria

- [ ] The parser, page list parser, usage text, JSON helpers and config key
  ops exist with the exact signatures.
- [ ] All listed cases pass.

## Progress Log

- Session 243 P06 implementation: added the typed invocation and pure parser,
  page-list parser, usage text, canonical JSON helpers and the 16-key config
  path getter/setter, with four focused Swift Testing suites. P06 source files
  compile in `swift build` (exit 0, `tmp/stria-v01-session-243/P06/build-rerun-1.log`);
  exact changed-file strict SwiftLint passes (`swiftlint-final.log`, exit 0),
  and all assigned Swift files are below 1000 lines (`line-count.log`).
- The root command `swift test --filter 'ParserTests|PageListTests|CLIJSONTests|ConfigKeyPathTests'`
  could not build the shared test target: another plan's P04 test has a
  throwing `#expect` at `Tests/StriaCoreTests/Imaging/P04ImagingTests.swift:19`,
  and the P05 `PreflightTests` compilation ended with Swift compiler signal 6.
  No foreign files were changed. An isolated SwiftPM test package under this
  plan's evidence directory compiled the unchanged P06 test copies against the
  current StriaCore source and passed all 10 tests in the four assigned suites
  (`isolated-test-rerun-1.log`, exit 0). This is scoped behavioral evidence;
  the shared root test command remains for serial integration verification.
- Completion criteria outcome: API/parser/config contracts implemented and
  the four assigned suites pass in isolated execution. Root aggregate testing
  remains blocked by P04/P05 test compilation as described above.
- Root test retry (`tmp/stria-v01-session-243/P06/test-rerun-2.log`, exit 1)
  confirms P05 `PreflightTests.swift` now compiles. The only current shared
  test target failure is the out-of-scope throwing assertion in
  `Tests/StriaCoreTests/Imaging/P04ImagingTests.swift:19`; the prior P05 signal
  6 was resolved by its owner after the earlier logged attempt.
