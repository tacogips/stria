# Memory growth investigation, 2026-10-06

The user observed stria-app exceeding 50 GB without noticing when growth began.
No stria-app process was running during investigation, so no allocation stack or
heap sample of that incident was available. No Stria-named diagnostic report was
found in the user or system DiagnosticReports directories. These changes remove confirmed eager
work and unbounded retention paths; they do not establish a single proven cause
of the reported peak.

## Findings and changes

- `ReaderViewModel.open()` started `expandAllPages` for every opened PDF. This read
  stored image BLOBs and decoded/re-encoded every page as PNG in the background,
  although the reader displays the original PDF through PDFKit. Opening now does
  no cache expansion. OCR, agent image access, and explicit image export continue
  to expand the individual pages they request.
- `ThumbnailListView` retained all visited thumbnails in a dictionary for the
  entire sidebar lifetime. Detached tasks also drew pages from the same PDFKit
  document used by the view. Visible rows now load 240-pixel thumbnails from the
  stored images and release them on disappearance. If an import has not stored a
  page yet, a cancellable task renders it using a separate, short-lived document.
- Stored image thumbnails decoded the original before scaling. They now use
  ImageIO thumbnail decoding with a maximum pixel dimension and an autorelease
  pool. PNG expansion also drains a pool around each conversion and file write.
- App imports previously started a task per file with no concurrency limit. Imports
  now run sequentially, including when more files are added to an existing queue.
  The tradeoff is lower throughput for simultaneous imports.
- A single import retained its PDFDocument across every rendered page. It now
  reopens the document after each 16 rendered pages, and performs page lookup
  inside the per-page autorelease pool. This bounds the document lifetime during
  rendering; it does not impose an absolute memory limit on PDFKit or a single
  unusually complex page. Reopening adds parsing overhead.
- Dismantling the PDF view explicitly detaches its document and coordinator view
  reference, allowing rendered resources to be released promptly.

## Additional inspection

SQLite statements finalize in deinit; the page image API selects only one BLOB.
SyncController prevents overlapping sync passes. The default local data directory
contained one one-page PDF and had sync disabled; it cannot be assumed to match
the environment of the reported incident. No document contents or credentials
were inspected.

A small isolated probe using the actual ImageCodec implementation rendered 40
240x180 thumbnails from a 2048x1536 JPEG. Both old and new paths peaked at about
35.2 MB RSS. This did **not** reproduce runaway growth or demonstrate a memory
reduction on that fixture; it rules out claiming that thumbnail decoding alone
explains the incident. The probe is temporary, at `/tmp/stria-memory-probe`.

## Validation

- `mise exec -- swiftlint --quiet`: passed with no violations.
- `mise exec -- swift test --filter 'ReaderViewModelTests|RenderCodecTests|PageImageCacheTests|DocumentsFacadeTests|LibraryViewModelTests|LibraryThumbnailTests|ImportTests'`:
  app/CLI/test build succeeded; 29 tests passed.
- `mise exec -- swift test`: all 242 tests in 60 suites passed. The initial full
  run exposed a test that assumed an agent reply completed in 50 milliseconds;
  that test passed alone. Its fixed sleeps now wait for observable completion
  with a bounded timeout, appropriate for lazy image preparation.
- `git diff --check`: passed.
- New checks cover reader thumbnail access without PNG expansion, explicit
  single-page expansion, encoded thumbnail dimensions and invalid input, and
  an 18-page import crossing the document-reopen boundary.
- The first focused build was interrupted by a source edit; the completed rerun
  above used the final Swift sources.

## Remaining verification

Reproduce with the affected PDF/data root and record process physical footprint
while opening, leaving the reader idle, scrolling thumbnails, importing, and
closing back to the library. If growth persists, take an Instruments Allocations
or VM Tracker recording before restarting to distinguish PDFKit resources,
image buffers, and agent/vendor allocations. The current regression tests do not
measure a long-running GUI session or prove elimination of the original 50 GB peak.
