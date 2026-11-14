# P04 Document Identity, PDF Inspection, Rendering, Image Codec, Outline, PNG Cache

**Status**: Completed (session 245; accepted by the test-integrity and adversarial gates and the post-join integration review comm-003268; moved to `impl-plans/completed/` in session 245 Step 8)
**planId**: P04
**Wave**: 1 of `impl-plans/active/stria-v01-session-245-dispatch.json` (stabilization wave)
**dependsOn**: none in this manifest (builds on completed P01, commit `2ea8582`; the code under review is in commit `0082491`)
**Design Reference**: `design-docs/specs/design-storage.md#document-identity`, `#import-pipeline` (steps 1, 5, 6), `#image-codec`, `#expanded-png-cache`; `design-docs/specs/architecture.md#testing-strategy`, `#implementation-rollout`

## Session-245 Stabilization (authoritative for this run)

### Intent

Commit `0082491` contains all six P04 production files and the five suites,
in `Tests/StriaCoreTests/Imaging/P04ImagingTests.swift`. A read-only audit
found that every signature matches the contracts below.

Four suites fail: `IdentityTests`, `InspectorTests`, `OutlineTests` and
`RenderCodecTests.rendersAtDPIWithCapAndRotation`. They write fixture files
directly into `paths.root`, but the shared helper `withTestDataRoot` never
creates that directory, so `CGDataConsumer(url:)` and `Data.write` fail
("Could not create PDF data consumer").

The design fixes this in the helper (`architecture.md#testing-strategy`),
and this plan owns that helper in the stabilization wave. This plan also
closes the test gaps the audit found. The original sections below stay the
baseline; where this section differs, this section wins.

Follow the Common Execution Protocol and the session-245 Stabilization
Protocol in `impl-plans/active/stria-00-overview.md`. Evidence logs go to
`tmp/stria-v01-session-245/P04/`.

### Ownership change

This plan is the only writer of
`Tests/StriaCoreTests/Support/TestDataRoot.swift` in wave 1. Every other
Support file stays read-only:

- `SamplePDFFactory.swift`
- `FakeOCRService.swift`
- `FakeAgentService.swift`

### Tasks

**P04-S1. `withTestDataRoot` creates the root directory.**

- File: `Tests/StriaCoreTests/Support/TestDataRoot.swift`.
- Before calling `body`, create `root` with
  `FileManager.default.createDirectory(at:withIntermediateDirectories: true,
  attributes: [.posixPermissions: 0o700])`.
- Keep the `defer` removal.
- Create only the root. Do not call `paths.ensureDirectories()` and do not
  create `originals/`, `cache/` or `logs/`. The test
  `PageImageCacheTests.explicitWriteDoesNotCreateCacheDirectory` asserts
  that `paths.cache` does not exist. `PathsTests` and `ConfigTests` must keep
  testing first-use creation.
- Do not change the signature of `withTestDataRoot` or of
  `makeTestEnvironment`.
- Red-green evidence: run
  `swift test --filter 'IdentityTests|InspectorTests|OutlineTests|RenderCodecTests'`
  before the change (`red-S1.log`, failures expected) and after it
  (`green-S1.log`, 0 failures).
- Do not change the failing tests themselves to create their own roots.
  The helper fix is the design decision, and it also protects P07-P11
  fixtures.

**P04-S2. `IdentityTests`: test a one-byte change, as the plan specifies.**

- Write a file, copy its bytes, flip the last byte, and write the result.
- The `docId` must differ.
- Keep the existing assertions.

**P04-S3. `PageImageCacheTests`: complete the validity assertions.**

After `expand`:

- `ImageCodec.pixelSize(ofImageAt:)` equals both the width and the height
  of the stored image;
- the file starts with the bytes `89 50 4E 47`;
- the `cache/<docId>` directory has POSIX permissions `0o700`.

**P04-S4. `InspectorTests`: cover the locked-PDF rule.**

- The design now says: reject `isLocked`; accept a PDF that is encrypted
  with an owner password only (`design-storage.md#import-pipeline` step 1).
  The code already does this (`PDFInspector.inspect` rejects `isLocked`).
- Add a test-local helper in the Imaging test file (not in Support) that
  writes a 1-page PDF through `CGContext(consumer:mediaBox:auxiliaryInfo)`.
  Use `kCGPDFContextUserPassword` and `kCGPDFContextOwnerPassword` for the
  locked case, and only `kCGPDFContextOwnerPassword` for the owner-only
  case.
- Cases:
  - user password set -> `invalidPDF`;
  - owner password only -> accepted, with `pageCount` 1.
- If the host's PDFKit reports `isLocked == false` for the user-password
  file, record the host behaviour in the Progress Log and keep only the
  owner-only assertion. Never assert something the host cannot produce.

### Accepted divergences (no change)

- `ImageCodec.encode` clamps `quality` to 0...1.
- `PageRenderer` throws `ioError` for a non-positive dpi or max dimension.
- `PDFInspection` is `Equatable`.
- `PageImageCache.expand` writes with `Data.write(options: .atomic)`, as the
  contract below specifies.

### Test integrity

No existing assertion may be removed or loosened. The four failing suites
must pass only because of P04-S1.

### Done criteria (mechanically checkable)

- `swift build --build-tests` exits 0.
- `swift test --filter 'IdentityTests|InspectorTests|RenderCodecTests|OutlineTests|PageImageCacheTests'`
  exits 0 with 0 failures, run at the end of the run (`focused-final.log`).
- `swift test --filter 'PathsTests|ConfigTests|SamplePDFTests'` exits 0.
  This checks that the helper change does not break first-use tests.
- `swiftlint lint Sources/StriaCore/Import Sources/StriaCore/Cache Tests/StriaCoreTests/Imaging Tests/StriaCoreTests/Support/TestDataRoot.swift`
  reports 0 violations.
- `git diff 0082491 -- Tests/StriaCoreTests/Imaging` removes no `#expect`
  or `#require` line.

## Session-243 Notes (still valid)

The tasks, contracts and paths are unchanged from session 241. Checked
against the wave-1 code:

- `Sources/StriaCore/Models/PageModels.swift:StoredPageImage` and
  `Models/DomainEnums.swift:ImageFormat` (`heic`, `jpeg`) exist;
- `Models/DocumentModels.swift:OutlineNode` already encodes `page` as an
  explicit null;
- `Paths/StriaPaths.swift` has `cacheDirectory(docId:)` and
  `cachedPage(docId:page:)` (the `page-%04d.png` format).

Use these and do not redefine them. `Tests/StriaCoreTests/Support/SamplePDFFactory.swift:makePDF(at:pages:pageSize:)`
generates the test PDFs. It writes no Title attribute, so the title test
sets one through PDFKit, as written below. Generated PDFs and images live
only in temp roots and are never committed.

## Intent and Context

This plan provides the pure PDFKit, ImageIO and CryptoKit building blocks
that the import coordinator (P07) and ask (P08) compose. None of these
types touch SQLite.

## Non-goals

- No import orchestration, no DB access, no OCR.
- No display rendering for the app: the app displays the original PDF
  through PDFView.

## writePaths

- `Sources/StriaCore/Import/DocumentIdentity.swift`
- `Sources/StriaCore/Import/PDFInspector.swift`
- `Sources/StriaCore/Import/PageRenderer.swift`
- `Sources/StriaCore/Import/ImageCodec.swift`
- `Sources/StriaCore/Import/OutlineExtractor.swift`
- `Sources/StriaCore/Cache/PageImageCache.swift`
- `Tests/StriaCoreTests/Imaging`
- `Tests/StriaCoreTests/Support/TestDataRoot.swift` (session 245: P04-S1)
- `impl-plans/active/stria-04-imaging-cache.md`

## sharedPaths

- `Sources/StriaCore/Models`
- `Sources/StriaCore/Errors/StriaError.swift`
- `Sources/StriaCore/Paths/StriaPaths.swift`
- `Tests/StriaCoreTests/Support`

## sharedPathNotes

- `{path: "Tests/StriaCoreTests/Imaging", intendedEdit: "directory"}`
- `{path: "impl-plans/active/stria-04-imaging-cache.md", intendedEdit: "append to the Progress Log section only"}`
- `{path: "Sources/StriaCore/Models", intendedEdit: "read-only; models owned by P01"}`
- `{path: "Sources/StriaCore/Errors/StriaError.swift", intendedEdit: "read-only"}`
- `{path: "Sources/StriaCore/Paths/StriaPaths.swift", intendedEdit: "read-only"}`
- `{path: "Tests/StriaCoreTests/Support", intendedEdit: "read-only except TestDataRoot.swift, which this plan owns in wave 1 (P04-S1)"}`
- `{path: "Tests/StriaCoreTests/Support/TestDataRoot.swift", intendedEdit: "withTestDataRoot creates only the root directory (0700) before the body; signatures unchanged"}`

## Contracts

All are public and `Sendable` (enums with static functions where stateless).

**`DocumentIdentity`**

- `static func sha256Hex(of url: URL) throws -> String`: streams the file
  in 1 MiB chunks through CryptoKit `SHA256` and returns lowercase hex.
  Failures are `ioError`.
- `static func docId(sha256Hex: String) -> String`: the first 16
  characters.

**`PDFInspector`**

- `struct PDFInspection { pageCount: Int, title: String }`.
- `static func inspect(url: URL) throws -> PDFInspection`:
  - throws `invalidPDF` when `PDFDocument(url:)` returns nil, when
    `isLocked` is true, or when `pageCount == 0`;
  - title is the trimmed `documentAttributes[PDFDocumentAttribute.titleAttribute]`
    when non-empty, else `url.deletingPathExtension().lastPathComponent`.
- Only `isLocked` PDFs are rejected. Encrypted PDFs that open without a
  password are readable, so they are accepted.

**`PageRenderer`**

- `static func render(page: PDFPage, dpi: Int, maxPixelDimension: Int)
  throws -> CGImage`:
  - start from the crop box bounds with the page rotation applied (swap
    width and height for 90 and 270 degrees);
  - `scale = dpi / 72`, reduced so `max(w, h) * scale <=
    maxPixelDimension`; pixel sizes are `Int(rounded)` with a minimum of 1;
  - draw into a `CGContext` in device sRGB, 8 bits per component, using
    `CGImageAlphaInfo.noneSkipLast`;
  - fill white, scale the context, then call
    `page.draw(with: .cropBox, to: context)`;
  - failures are `ioError`.

**`ImageCodec`**

- `static func encode(_ image: CGImage, preferred: ImageFormat, quality:
  Double) throws -> StoredPageImage`:
  - HEIC (`public.heic`) through `CGImageDestinationCreateWithData` with
    `kCGImageDestinationLossyCompressionQuality`;
  - if creation or finalize fails, fall back to JPEG (`public.jpeg`) at the
    same quality;
  - the returned `format` is the one actually produced, and width and
    height come from the image.
- `static func decode(_ data: Data) throws -> CGImage`: through
  `CGImageSource`. Failures are `ioError`.
- `static func pngData(_ image: CGImage) throws -> Data`
- `static func pixelSize(ofImageAt url: URL) -> (width: Int, height: Int)?`:
  reads `CGImageSourceCopyPropertiesAtIndex` (`kCGImagePropertyPixelWidth`
  and `kCGImagePropertyPixelHeight`) without decoding the pixels.

**`OutlineExtractor`**

- `static func extract(from document: PDFDocument) -> [OutlineNode]`:
  - walk `outlineRoot` recursively;
  - `page` is `document.index(for: destination.page) + 1`, or nil when
    there is no destination or page;
  - a missing root returns `[]`.
- `static func encodeJSON(_ nodes: [OutlineNode]) -> String` and
  `static func decodeJSON(_ json: String) -> [OutlineNode]` (`[]` when the
  JSON is invalid).

**`PageImageCache`**

```
public struct PageImageCache: Sendable {
  public init(paths: StriaPaths)
  public func validCachedURL(docId: String, page: Int, width: Int, height: Int) -> URL?
  public func expand(docId: String, page: Int, image: StoredPageImage) throws -> URL
  public func write(image: StoredPageImage, to url: URL) throws
}
```

- `validCachedURL` returns the URL only when the file exists, is non-empty,
  and `pixelSize` equals the given width and height.
- `expand`:
  - creates `cacheDirectory(docId:)` with permissions 0700 when missing;
  - decodes, converts to PNG, and writes with `Data.write(options:
    .atomic)` to `cachedPage(docId:page:)`;
  - returns the absolute URL.
- `write(image:to:)` is the same, but for an explicit output URL. It
  creates the parent directory and never touches the cache.
- Callers check `validCachedURL` first, to avoid reading the BLOB. `expand`
  itself always rewrites the file.

## Pitfalls

- `PDFDocument` and `PDFPage` are not Sendable. Never store them in these
  types. Take them as parameters only.
- HEIC encoding may be unavailable on CI or virtualized hosts. Tests must
  accept heic or jpeg for the default path and must not assert the size
  ratio.
- Do not hold every page image in memory. These functions handle one page
  at a time.
- Do not add a resource bundle.

## Tests (`Tests/StriaCoreTests/Imaging/`)

Generate PDFs with `SamplePDFFactory`.

`IdentityTests`:

- same file copied to two paths -> same sha and docId
- one byte changed -> different docId
- docId has 16 lowercase hex characters

`InspectorTests`:

- non-PDF file -> `invalidPDF`
- generated PDF with no Title -> title equals the file name stem
- PDF with Title "Report" set through PDFKit attributes and `write(to:)` -> "Report"
- pageCount is correct

`RenderCodecTests`:

- 612x792 page at 150 dpi -> 1275x1650
- at 600 dpi with maxPixelDimension 4096 -> the longest side is 4096 or less
- page rotation 90 (set `page.rotation = 90`) -> width > height
- encode with preferred heic -> format heic or jpeg, and decode round-trip keeps width and height
- preferred jpeg -> format jpeg
- `pngData` starts with the PNG signature `89 50 4E 47`

`OutlineTests`:

- build a PDFOutline with 2 children (one with a destination on page 2, one without), set `outlineRoot`, write and reopen -> `[{title, page: 2}, {title, page: nil}]`
- JSON encode then decode round-trip
- no outline -> `[]`

`PageImageCacheTests`:

- `expand` -> file at `cache/<docId>/page-0001.png`, a valid PNG with the expected size
- `validCachedURL` after expand -> non-nil
- a file truncated to 0 bytes -> nil
- a file with a different size (write a 1x1 PNG) -> nil, and `expand` rewrites it
- `write(to:)` an explicit URL -> the cache dir is not created

## Verification

- `swift build` -> exit 0 (`tmp/verify/P04/build.log`)
- `swift test --filter Imaging` (or the suite names above) -> all pass (`tmp/verify/P04/test.log`)
- `swiftlint lint Sources/StriaCore/Import Sources/StriaCore/Cache Tests/StriaCoreTests/Imaging`
  -> exit 0 (`tmp/verify/P04/lint.log`). The `Import` folder contains only
  this plan's files during wave 2; P07 adds `ImportCoordinator.swift` in
  wave 3.

## Done Criteria

- [ ] All contracts compile with the exact signatures.
- [ ] The codec falls back to JPEG.
- [ ] Cache validity is checked without decoding pixels.
- [ ] Tests pass.

## Progress Log

- Implemented all six P04 production contracts and the five imaging test suites in `Tests/StriaCoreTests/Imaging/P04ImagingTests.swift`. Isolated Swift 6 typechecking passed (`tmp/stria-v01-session-243/P04/logs/p04-source-typecheck.log`, exit 0); selected changed-file strict SwiftLint passed (`tmp/stria-v01-session-243/P04/logs/swiftlint.log`, exit 0); the P04 Swift file-length gate passed (`tmp/stria-v01-session-243/P04/logs/file-length.log`, exit 0).
- Full `swift build` and `swift test --filter 'IdentityTests|InspectorTests|RenderCodecTests|OutlineTests|PageImageCacheTests'` both stop before completing module compilation/test discovery (exit 1). Diagnostics are confined to foreign shared-tree files owned by P03/P06: `Sources/StriaCore/Storage/StriaStore+Documents.swift`, `Sources/StriaCore/Storage/StoreSupport.swift`, `Sources/StriaCore/Storage/SQLiteConnection.swift`, and `Sources/StriaCore/CLI/CommandLineParser.swift`. Their complete logs are `tmp/stria-v01-session-243/P04/logs/swift-build-retry.log` and `tmp/stria-v01-session-243/P04/logs/imaging-tests.log`. Behavioral suite completion remains pending serial repair and verification; no foreign files were changed.

### Session 245

- P04-S1: `withTestDataRoot` creates only its unique root with POSIX mode `0700`, before the body; it keeps deferred cleanup and unchanged signatures. The red run failed as expected on absent-root fixtures (`logs/red-S1.log`, exit 1, 6 tests / 5 failures); after the helper change, the green run passed (`logs/green-S1.log`, exit 0, 7 tests / 0 failures).
- P04-S2: the identity fixture now copies the original bytes and XOR-flips the last byte; all original `#expect` assertions remain.
- P04-S3: cache tests now check stored width and height, PNG signature `89 50 4E 47`, and cache directory permissions `0700`, while preserving invalid-cache rewrite and explicit-write coverage.
- P04-S4: inspector tests cover user-password locked rejection and owner-password-only acceptance. The host probe reports `PDFDocument.isLocked == true` for the generated user-password fixture (`logs/host-locked-capability.log`, exit 0); the test's locked assertion ran and passed.
- P04 done criteria: contracts compile, JPEG fallback is covered by the existing codec contract, cache validity uses image properties without decoding, and all assigned suites pass. `swift build --build-tests` passed (`logs/build-build-tests.log`, exit 0); first-use tests passed 7/7 (`logs/first-use-tests.log`); strict changed-file SwiftLint passed for the two Swift files (`logs/swiftlint-changed-files.log`); assertion-removal and Swift file-length gates passed (`logs/assertion-removal-gate.log`, `logs/swift-file-length-gate.log`). Final focused P04 suite evidence is recorded after this progress update in `logs/focused-final.log`.
- Implementation self-check found no removed assertions or unowned edits. Formal test-integrity/adversarial review and serial finalization remain downstream workflow steps.
- Resume verification reran the combined-tree build and assigned behavior after the Step 6 output flagged the expected pre-change red run: `swift build --build-tests` passed (`logs/resume-build-build-tests.log`, exit 0), the P04 focused suites passed 9/9 (`logs/resume-focused-final.log`), and the first-use suites passed 7/7 (`logs/resume-first-use-tests.log`). Exact changed-file strict SwiftLint passed (`logs/resume-swiftlint-changed-files.log`); assertion preservation and the 1000-line gate passed (`logs/resume-assertion-integrity.log`, `logs/resume-file-length.log`). Formal reviews and serial integration remain downstream.
- 2026-10-02 (session 245, Step 8 serial finalization): accepted by the test-integrity and adversarial gates and the post-join integration review (comm-003268). Combined-tree evidence in `tmp/stria-v01-session-245/join/wave-5/`: `swift build --build-tests` exit 0 (`build-tests.log`), `swift test` 120 tests in 36 suites exit 0 (`swift-test-full.log`), `scripts/cli-smoke.sh` SMOKE OK exit 0 (`cli-smoke.log`). Moved to `impl-plans/completed/`. The Done Criteria checkboxes are kept as authored (intent snapshot); this entry records that they are met.
