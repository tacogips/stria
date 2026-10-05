# OCR as JSON with tags: decisions

Request (2026-10-05): OCR should answer JSON with a `body` field and the
page's main words, people, events and so on as a `tags` array; when the AI's
JSON is in the wrong shape, retry with backoff, with the retry limit set in
Settings.

Decisions made while implementing (defaults, revisable):

- Tags are plain strings (no kind such as person or event), 3 to 20 asked
  for, at most 40 kept.
- The JSON contract is appended by Stria to every model OCR prompt, so a
  custom OCR prompt cannot break it; the editable prompt only describes the
  transcription.
- `ocr.formatRetries` defaults to 2 (0...5). Backoff is 2, 4, 8, 16, 30
  seconds. Only malformed replies are retried this way; vendor errors keep
  their existing handling.
- Tags are stored but not indexed for search (the body already is); clicking
  a tag in the Summary tab searches every PDF's text for it.
- The local `pdf-text-layer` vendor has no tags.
- Pages OCRed before this change have no tags until they are OCRed again.
