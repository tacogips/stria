# Empty OCR Replies From Gateway Vendors

## Status

Pending. The default below is applied.

## Question

The default OCR prompt tells the model to output nothing for a page without
text. The OCR reply check
(`../specs/design-agent-integration.md#ocr-reply-check`) treats an empty
gateway reply as `failed`, because an agent that never received the page
image can also return nothing. As a result, truly blank pages OCR'd by a
gateway vendor end up `failed` and are retried on every `--retry-failed`.
Should that change?

## Default Applied

- An empty gateway OCR reply is `failed` with the reason `OCR reply was
  empty; the page image may not have reached the model`. The issue asks for
  this behavior.
- `pdf-text-layer` still stores an empty result as `done`.
- The default OCR prompt is unchanged.

## Open Point

Keep the default, or change the default prompt so a blank page returns a
fixed marker that stria stores as `done` with empty text.
