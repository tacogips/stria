# stria

stria is a macOS PDF reader with an OCR-indexed SQLite page store, continuous PDF reading, an agent chat pane, and a JSON CLI that lets external agents search documents and retrieve page images.

## Requirements

- macOS 14 or later
- Swift 6 toolchain: run `mise install`

## Build, test, lint and smoke

```sh
mise run build
mise run test
mise run lint
mise run smoke
```

`mise run test` runs offline with fake OCR and agent services and needs no vendor credentials. `mise run smoke` (`scripts/cli-smoke.sh`) builds the CLI, generates sample PDFs and, against a temporary `STRIA_HOME`, runs `import --no-ocr`, `list`, `page image`, OCR through the local `pdf-text-layer` vendor, cross-document English and Japanese `search`, and `history`; it prints `SMOKE OK` on success and never touches `~/.local/stria`.

## Running

```sh
swift run stria --help
swift run stria-app
```

To try the app without touching your real library, run `STRIA_HOME=$(mktemp -d) swift run stria-app`.

## App

`stria-app` is a SwiftUI app for macOS 14 and later:

- Library: previously imported PDFs with title, page count and import/OCR progress. Import with the toolbar button, `Cmd-O` or drag and drop. Opening a document expands its page-image cache in the background.
- Reader: a left sidebar with Contents (PDF outline, current section highlighted), Thumbnails and OCR search results from the toolbar search field. The center PDF view scrolls continuously and vertically. The toolbar shows an `n / N` page field, and the reader restores the last-read page for each document.
- Agent inspector: a right pane with a scope picker (This page, Nearby pages, Whole PDF), a transcript with page-citation chips that jump to the cited page, New Chat, and history for This page or This PDF.

| Command | Shortcut |
| --- | --- |
| Import PDF | `Cmd-O` |
| Show/Hide Agent | `Cmd-Opt-0` |
| Library | `Cmd-Shift-L` |
| Go to Page | `Cmd-Opt-G` |
| Next / Previous Page | `Cmd-Opt-Down` / `Cmd-Opt-Up` |
| Send question | `Cmd-Return` in the input field |
| New Chat | `Cmd-Shift-N` |

## Data root

The default data root is `~/.local/stria`. `STRIA_HOME` overrides it, and the CLI `--home <path>` option takes precedence over the environment variable. The root contains:

- `stria.sqlite`: documents, compressed page images, OCR text, chat history and agent runs
- `originals/`: byte-identical imported PDFs
- `cache/`: expanded `page-NNNN.png` files for OCR and agent tools; safe to delete
- `config.json`: render, OCR and agent settings
- `logs/`: per-call JSONL records without secrets or page image data

## Configuration

The first data-root use creates `config.json` with defaults. Inspect or edit settings with `stria config get [<key>]` and `stria config set <key> <value>`. Configuration stores API-key environment variable names, never secret values. See [default agent configuration](design-docs/user-qa/default-agent-config.md).

OCR and agent calls go through [agent-gateway](https://github.com/tacogips/agent-gateway). `ocr.vendor` and `agent.vendor` accept an agent-gateway vendor (`claude-code`, `codex`, `cursor`, `cursor-api`, `openai`, `anthropic`, `gemini`, `openrouter`). `ocr.vendor` also accepts `pdf-text-layer`, which reads the PDF's embedded text locally with no model call. If OCR is unavailable, for example because the API-key environment variable is unset, import still succeeds and pages stay pending so `stria ocr` can run them later.

## CLI for agents

`stria [--home <path>] <command> ...` prints one JSON object on stdout for success and is intended primarily for agent tools. `--json` is accepted and has no effect; `--help` and `--version` never create the data root.

- `stria import <pdf> [--no-ocr]`: import a PDF and optionally run OCR; prints the document ID
- `stria ocr <docId> [--pages <list>] [--retry-failed]`: run or retry page OCR
- `stria list`: list imported PDFs and OCR progress
- `stria show <docId>`: show document metadata and outline
- `stria page image <docId> <page> [--output <path>]`: expand and return a page PNG path
- `stria page text <docId> <page>`: return page OCR text
- `stria search <query> [--doc <docId>] [--limit <n>]`: search OCR text across PDFs or within one PDF
- `stria ask <question> [--doc <docId>] [--page <n>] [--query <terms>] [--limit <n>]`: retrieve context pages and ask the configured agent; `--page` requires `--doc`, and `--limit` caps the context pages
- `stria history [--doc <docId>] [--page <n>] [--limit <n>]`: read saved conversations
- `stria config get [<key>]` / `stria config set <key> <value>`: inspect or edit configuration
- `stria paths`: print resolved data-root paths

On failure, stdout is empty and stderr gets `{"error":{"code":"...","message":"..."}}`.

| Exit | Meaning |
| --- | --- |
| 0 | success |
| 1 | internal, IO or database error |
| 2 | usage error or invalid input, including invalid or password-locked PDFs |
| 3 | document, page or relevant pages not found |
| 4 | OCR or agent unavailable (config, credential environment variable, integration) |
| 5 | OCR or agent call failed; a failed `ask` is still saved to history |

See [the CLI contract](design-docs/specs/command.md) for the JSON shapes.

### Agent Usage

1. Run `stria search "<key phrase>"` to find matching document IDs and page numbers. Add `--doc <docId>` to narrow the search.
2. Run `stria page image <docId> <page>` for a matching page and read the PNG at the returned path. `stria page text` can also return its OCR text.
3. Answer using the retrieved page and cite the document ID and page. Use `stria show <docId>` to inspect its outline.

Alternatively, `stria ask "<question>"` performs retrieval and answering with the configured agent and saves the conversation.

## Packaging

Homebrew formula and cask paths use the name `stria`. Release packaging currently ships the CLI binary only. Run the app with `swift run stria-app`; app-bundle distribution is not part of v0.1. See [Homebrew packaging](packaging/homebrew/README.md) and [app distribution](design-docs/user-qa/app-distribution.md).

## Design docs

Architecture, storage, agent integration, CLI and app UI designs are in [`design-docs/specs/`](design-docs/specs/).
