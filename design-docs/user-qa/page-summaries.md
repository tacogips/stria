# Page summaries: decisions

Request (2026-10-05): optionally summarize each page after OCR, with a setting
for doing it automatically; use the previous page's OCR text and summary when
summarizing a page; keep summaries out of search; show them in a new Summary
tab of the right pane; allow redoing them like OCR, with extra instructions;
give summaries their own model and a default, editable, restorable prompt; let
the output language be chosen from a select box and inserted into the prompt
template as `{language}`.

Decisions made while implementing (defaults, revisable):

- `summary.autoRunAfterOCR` defaults to false and `summary.vendor` to null,
  matching the rule that a fresh install calls nothing the user did not pick.
- `summary.language` defaults to `auto` ("Same as the page"); the select box
  also lists eleven languages, and the CLI accepts any name.
- API vendors reuse the Agent API Keys table instead of a separate key field.
- Pages are summarized strictly in page order, one at a time, so a page can
  use the fresh summary of the page before it.
- Re-OCR marks a page's summary stale; the auto-run after that OCR replaces
  it, otherwise the Summary tab shows the stale icon.
- The CLI does not auto-summarize after `import`/`ocr`; `stria summarize`
  runs summaries explicitly.
- The redo sheet also offers a per-run language override.
