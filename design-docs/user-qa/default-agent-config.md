# Default Agent, OCR and Image Settings

## Status

Answered (2026-10-02): no vendor is configured by default.

## Question

Which vendor and model should OCR and the agent use by default, and which
page image format and resolution should be stored?

## Decision

- OCR and agent: no default vendor. `ocr.vendor` and `agent.vendor` are null
  until the user chooses them in the app's Settings window or with
  `stria config set`. The user's words: an unintended API must never be
  selected; when unset, the user picks vendor and model from Settings.
- OCR trigger: `ocr.autoRunOnImport` (default true) decides between OCR at
  import time and a manual "Run OCR" button; both are available.
- Images: HEIC at quality 0.75 and 150 DPI (JPEG fallback), with the longest
  side capped at 4096 px.

Rationale:

- A fresh install launched without credentials used to report "environment
  variable ANTHROPIC_API_KEY is not set" in the chat pane; the user did not
  choose Anthropic and should not see it. Choosing explicitly also covers the
  Claude Code / Codex CLI vendors that need no key.
- HEIC roughly halves storage compared with JPEG while keeping text legible
  for OCR.
- Vendor ids must be `GatewayVendor` raw values of the agent-gateway revision
  pinned in `Package.swift`.
