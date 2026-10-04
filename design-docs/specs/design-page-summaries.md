# Page Summaries

## Status

Implemented (schema v4).

## Goal

An optional summary of each page, written after OCR, shown in the agent
pane's Summary tab. Each page is summarized with the previous page's OCR text
and summary as context, so a sentence, list or table that continues across a
page break is understood. Summaries are reading aids only: they are never
indexed or searched, and `ask` retrieval does not read them.

## Config (`summary`)

| Key | Default | Meaning |
| --- | --- | --- |
| `summary.vendor` | `null` | agent-gateway vendor; null = summaries off (nothing is called) |
| `summary.model` | `null` | model id; required for every vendor (preflight) |
| `summary.prompt` | `null` | prompt template; null = `PageSummaryDefaults.prompt` |
| `summary.language` | `"auto"` | language name inserted at `{language}`; `auto` = the page's own language |
| `summary.autoRunAfterOCR` | `false` | the app summarizes the pages an OCR run finished |
| `summary.timeoutSeconds` | 300 | bound for one page's call (10...3600) |

API vendors use the key variable from `agent.credentials.<vendor>` (Settings >
Agent API Keys); there is no separate summary key field. `summary.language`
must be 1...64 characters; Settings offers `PageSummaryLanguage.options`
("Same as the page", English, Japanese, Chinese (Simplified), Chinese
(Traditional), Korean, French, German, Spanish, Portuguese, Italian,
Russian) and keeps a custom name set through the CLI.

### Prompt template

`PageSummaryDefaults.render(template, language:)` replaces every
`{language}` with the language name, or with "the same language as the target
page's text" for `auto`. The default template asks for three to six short
bullet points about the target page only, treats the previous page as context,
forbids invented content and asks for the summary alone. Settings shows the
template in an editor with "Using the default prompt." / "Custom prompt.", a
warning when `{language}` is missing, and Reset to Default; text equal to the
default is stored as null so a later default reaches users who never edited it.

## Request

`PageSummaryCoordinator` runs pages one at a time in ascending order, so page
N-1's summary (possibly written earlier in the same run) is available for
page N. Per page:

1. The page must have `ocr_status = done`; other pages are reported in
   `skipped` and left alone.
2. A page whose OCR text is empty is stored as `done` with an empty summary,
   without a model call (the Summary tab says "This page has no text.").
3. Otherwise one `AgentService.ask` with no context pages and no history:
   - system prompt: the rendered template;
   - user message: `<previous_page page="N-1">` with `<text>` (the last 4,000
     characters of its OCR text) and `<summary>` (its done summary), when
     either exists; `<target_page page="N">` with the first 24,000
     characters; then "Additional instructions for this summary:" and the
     run's instruction, if any; then "Summarize the target page.".
4. The reply is cleaned with `OCRTextPostProcessor.clean` (code fences
   removed); an empty reply is a failure.

An `unavailable` service error (no vendor, missing key, no model) stops the
run and is returned as `unavailableReason`; a `failed` error is stored on the
page (`status = failed`, `error`) and the run continues. Cancellation stops
the run without writing the current page.

## Storage

Migration 4 adds a table that no search query reads:

```
page_summaries(
  document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
  page_number INTEGER NOT NULL CHECK(page_number >= 1),
  status TEXT NOT NULL CHECK(status IN ('done','failed')),
  summary TEXT, error TEXT, language TEXT NOT NULL, instruction TEXT,
  vendor TEXT NOT NULL, model TEXT,
  source_ocr_updated_at TEXT,   -- pages.ocr_updated_at the summary was written from
  updated_at TEXT NOT NULL,
  PRIMARY KEY(document_id, page_number))
```

- `savePageSummary` upserts; a failed attempt keeps the previous summary text
  and records the error.
- A summary is stale when the page's `ocr_updated_at` differs from
  `source_ocr_updated_at` (the page was OCRed again).
- `pagesNeedingSummary` lists OCRed pages without a current `done` summary
  (none, failed or stale).
- Removing a document cascades its summaries.

## App

- `LibraryViewModel.summarizePages(documentId:range:instruction:language:)`
  maps `OCRRange` (`.remaining` = pages needing a summary, `.all`,
  `.pages("1-3, 8")`) to a run. Runs for one document are queued behind each
  other (`summaryTasks`) so page order holds; `summaryProgress` and
  `summaryRevision` drive the Summary tab.
- With `summary.autoRunAfterOCR`, the app starts a background run after every
  OCR run it starts: the processed pages after Run OCR, and every page needing
  a summary after an import with OCR. The CLI never summarizes on its own;
  agents call `stria summarize`.
- Summary tab (third segment of the agent pane, `doc.plaintext`): "Page N",
  a stale icon, a spinner with "p. N (k/total)" during a run, and a button
  that opens the run sheet. The body shows the summary (selectable text), a
  failure notice with the error, the run's instructions, and "language ·
  vendor model · age". Empty states: summaries off (with Open Settings...),
  page not OCRed yet, and "No summary for this page yet." with Summarize
  Pages....
- `SummaryRunSheet`: the shared page-range radio choices (current page
  prefilled in "Pages"; "Pages without a current summary (N)"; "All N
  pages"), a Language picker defaulting to `summary.language`, an optional
  Instructions editor, and a line naming the vendor and model, the page count
  and that existing summaries of the chosen pages are replaced.
- Settings > Page Summaries: "Summarize each page after OCR", vendor, model
  (with live fetch for API vendors), a note on the key variable, Language,
  and the prompt template editor with Reset to Default.

## CLI

- `stria page summary <docId> <page>`: `{"docId", "page", "status"
  ("done" | "failed" | "none"), "summary", "error", "language",
  "instruction", "vendor", "model", "stale", "updatedAt"}` with explicit
  nulls; a page beyond the document is `pageNotFound` (exit 3).
- `stria summarize <docId> [--pages <list>] [--instruction <text>]
  [--language <name>]`: without `--pages` it summarizes pages needing a
  summary; prints `{"docId", "summarized", "skipped", "failures"}`. No vendor
  configured is `serviceUnavailable` (exit 4); a bad page list is a usage
  error (exit 2).

## Tests

`PageSummaryTests` (order and previous-page context, staleness after OCR,
redo with instructions and language, failure keeps the old summary, blank and
not-OCRed pages, unconfigured vendor, app auto-run on and off, config keys),
`SummaryCLITests`, `SettingsViewModelTests` (summary fields) and
`MigrationTests` (version 4, `page_summaries`).
