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

## Running

```sh
swift run stria --help
swift run stria-app
```

## Data root

The default data root is `~/.local/stria`. `STRIA_HOME` overrides it, and the CLI `--home <path>` option takes precedence over the environment variable. The root contains:

- `stria.sqlite`: documents, compressed page images, OCR text, chat history and agent runs
- `originals/`: byte-identical imported PDFs
- `cache/`: expanded `page-NNNN.png` files for OCR and agent tools; safe to delete
- `config.json`: render, OCR and agent settings
- `logs/`: per-call JSONL records without secrets or page image data

## Configuration

The first data-root use creates `config.json` with defaults. Inspect or edit settings with `stria config get` and `stria config set <key> <value>`. Configuration stores API-key environment variable names, never secret values. See [default agent configuration](design-docs/user-qa/default-agent-config.md).

## CLI for agents

`stria` emits JSON for successful commands and is intended primarily for agent tools:

- `stria import <pdf> [--no-ocr]`: import a PDF and optionally run OCR
- `stria ocr <docId> [--pages <list>] [--retry-failed]`: run or retry page OCR
- `stria list`: list imported PDFs and OCR progress
- `stria show <docId>`: show document metadata and outline
- `stria page image <docId> <page>`: expand and return a page image path
- `stria page text <docId> <page>`: return page OCR text
- `stria search <query> [--doc <docId>] [--limit <n>]`: search OCR text across PDFs or within one PDF
- `stria ask <question> [--doc <docId>] [--page <n>]`: retrieve context and ask the configured agent
- `stria history [--doc <docId>] [--page <n>]`: read saved conversations
- `stria config get/set`: inspect or edit configuration
- `stria paths`: print resolved data-root paths

### Agent Usage

1. Run `stria search "<key phrase>"` to find matching document IDs and page numbers. Add `--doc <docId>` to narrow the search.
2. Run `stria page image <docId> <page>` for a matching page and read the PNG at the returned path. `stria page text` can also return its OCR text.
3. Answer using the retrieved page and cite the document ID and page. Use `stria show <docId>` to inspect its outline.

Alternatively, `stria ask "<question>"` performs retrieval and answering with the configured agent and saves the conversation.

## Packaging

Homebrew formula and cask paths use the name `stria`. Release packaging currently ships the CLI binary only. Run the app with `swift run stria-app`; app-bundle distribution is not part of v0.1. See [Homebrew packaging](packaging/homebrew/README.md) and [app distribution](design-docs/user-qa/app-distribution.md).

## Design docs

Architecture, storage, agent integration, CLI and app UI designs are in [`design-docs/specs/`](design-docs/specs/).
