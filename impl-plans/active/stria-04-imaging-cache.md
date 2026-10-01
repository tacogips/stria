# P04 Document Identity, PDF Inspection, Rendering, Image Codec, Outline, PNG Cache

**Status**: Ready (re-issued in session 243)
**planId**: P04
**Wave**: 1 of the session-243 manifest
**dependsOn**: none in this manifest (builds on completed P01, commit `2ea8582`)
**Design Reference**: `design-docs/specs/design-storage.md#document-identity`, `#import-pipeline` (steps 1, 5, 6), `#image-codec`, `#expanded-png-cache`; `design-docs/specs/architecture.md#implementation-rollout`

## Session-243 Revision

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
- `{path: "Tests/StriaCoreTests/Support", intendedEdit: "read-only; test helpers owned by P01"}`

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

- (worker appends entries here)
