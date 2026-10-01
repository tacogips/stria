# Default Agent, OCR and Image Settings

## Status

Pending. Defaults are applied, and every value can be changed with
`stria config set`.

## Question

Which vendor and model should OCR and the agent use by default, and which
page image format and resolution should be stored?

## Default Applied

- OCR: vendor `anthropic`, model `claude-sonnet-5-5`, credential env var
  `ANTHROPIC_API_KEY`, concurrency 2.
- Agent: vendor `anthropic`, model `claude-opus-5-5`, credential env var
  `ANTHROPIC_API_KEY`.
- Images: HEIC at quality 0.75 and 150 DPI (JPEG fallback), with the longest
  side capped at 4096 px.

Rationale:

- An API vendor accepts image content blocks without depending on a locally
  installed agent CLI.
- HEIC roughly halves storage compared with JPEG while keeping text legible
  for OCR.
- Vendor ids must be `GatewayVendor` raw values of the agent-gateway revision
  pinned in `Package.swift`.

## Open Point

Confirm these defaults, or name the preferred vendor and model (for example
`claude-code` or `codex` through their CLI login).
