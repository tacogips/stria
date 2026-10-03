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

The first data-root use creates `config.json` with no OCR or agent vendor: nothing is called until you choose one. In the app, open Settings (Agent > Settings…, or `Cmd-,`) and pick an OCR vendor and an agent vendor, a model, and for API vendors the name of the environment variable that holds the key; the library shows a banner with a Settings link until both are set. Settings also has a "Run OCR automatically after import" switch (`ocr.autoRunOnImport`); when it is off, pages wait until you choose Run OCR for a document (toolbar button or context menu). The agent's system prompt can be edited there and reset to the default. From the CLI, use `stria config get [<key>]` and `stria config set <key> <value>` (for example `stria config set ocr.vendor claude-code`, `stria config set ocr.model claude-sonnet-5-5`). Configuration stores API-key environment variable names, never secret values. See [default agent configuration](design-docs/user-qa/default-agent-config.md).

OCR and agent calls go through [agent-gateway](https://github.com/tacogips/agent-gateway). `ocr.vendor` and `agent.vendor` accept an agent-gateway vendor (`claude-code`, `codex`, `cursor`, `cursor-api`, `openai`, `anthropic`, `gemini`, `openrouter`). `ocr.vendor` also accepts `pdf-text-layer`, which reads the PDF's embedded text locally with no model call. If OCR is unavailable, for example because the API-key environment variable is unset, import still succeeds and pages stay pending so `stria ocr` can run them later.

API vendors (`openai`, `anthropic`, `gemini`, `openrouter`) receive page images as image content. The CLI vendors (`claude-code`, `codex`, `cursor`) cannot receive image content through agent-gateway, so for them stria puts the absolute path of each page PNG under `cache/` in the prompt and tells the agent to open the file. The agent session runs in `cache/`, so the CLI agent needs permission to read files there. See [vendor image capability](design-docs/specs/design-agent-integration.md#vendor-image-capability).

A gateway OCR reply that is empty, or that says no image was received, is recorded as a `failed` page with a fixed error instead of `done`, and `stria ocr <docId> --retry-failed` runs it again. The OCR prompt asks the model to answer exactly `[NO TEXT]` for a page without text; that reply is stored as `done` with empty text, so blank and figure-only pages are not retried forever. Every model call is bounded by `ocr.timeoutSeconds` (default 300) and `agent.timeoutSeconds` (default 600); a call that exceeds its bound is cancelled and recorded as failed. Every gateway vendor, including the CLI vendors, needs a `model`; a null model is reported as unavailable before any call. See [OCR reply check](design-docs/specs/design-agent-integration.md#ocr-reply-check) and [empty OCR replies](design-docs/user-qa/ocr-empty-reply.md).

## CLI for agents

`stria [--home <path>] <command> ...` prints one JSON object on stdout for success and is intended primarily for agent tools. `stria --help` carries the output contract and the agent workflow, so an agent can learn the tool from the help text alone. `--json` is accepted and has no effect; `--help` and `--version` never create the data root.

- `stria import <pdf> [--ocr | --no-ocr]`: import a PDF; OCR runs when `ocr.autoRunOnImport` is on (the default) or `--ocr` is given, and never with `--no-ocr`; prints the document ID
- `stria ocr <docId> [--pages <list>] [--retry-failed]`: run or retry page OCR
- `stria list`: list imported PDFs and OCR progress
- `stria show <docId>`: show document metadata and outline
- `stria remove <docId>`: delete a document with its stored copy, page images, OCR text and chat history
- `stria page image <docId> <page> [--output <path>]`: expand and return a page PNG path
- `stria page text <docId> <page>`: return page OCR text
- `stria search <query> [--doc <docId>] [--limit <n>]`: search OCR text across PDFs or within one PDF; terms shorter than 3 characters use LIKE matching ranked by occurrence count
- `stria ask <question> [--doc <docId>] [--page <n>] [--query <terms>] [--limit <n>] [--thread <id>]`: retrieve context pages and ask the configured agent; `--page` requires `--doc`, `--limit` caps the context pages, and `--thread` continues an earlier conversation. The output lists `citations` (pages the answer cites) and `contextPages` (every page sent)
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

## Keyboard shortcuts in the reader

Single keys, in the style of chilla, that pause while a text field is being edited:

- `Esc`: close search results, or back to the library
- `Shift+L` / `Shift+R`: collapse or expand the left pane / the agent pane
- `/` (or `Cmd-F`): search the OCR text in a popup; results open in the center pane with page thumbnails and highlighted hits, `Esc` returns
- `i`: focus the agent chat input
- `Ctrl+D` / `Ctrl+U`: page the PDF down / up; `j` / `k`: scroll one line
- `Shift+D`: toggle light and dark mode (light is the default; Settings > Appearance also offers "System")
- `?` (or Help > Keyboard Shortcuts, `Cmd-/`): show the full list, including the menu shortcuts (`Cmd-Opt-G` go to page, `Cmd-Opt-Up/Down` previous/next page, `Cmd-+`/`Cmd--` zoom, `Cmd-Return` send, `Cmd-.` cancel, `Cmd-Shift-L` library)

## Packaging

Install with Homebrew (macOS 14+, Apple Silicon or Intel):

```bash
brew install --cask tacogips/homebrew-tap/stria
```

The cask installs the signed and notarized `Stria.app` and links its `stria` command line tool (`Stria.app/Contents/MacOS/stria`) into the Homebrew prefix. When Stria is opened from Finder or the Dock, it reads your login shell's environment once at startup, so `claude` / `codex` and API key variables resolve as they do in a terminal.

Release (maintainers; Apple credentials come from kinko):

```bash
git tag v<version> && git push origin v<version>
kinko exec --env APPLE_SIGNING_IDENTITY,APPLE_ID,APPLE_PASSWORD,APPLE_TEAM_ID -- \
  mise run release:homebrew-cask-local -- v<version>
# then commit and push ../homebrew-tap/Casks/stria.rb
```

The build assembles `Stria.app` (icon from `scripts/make-app-icon.swift`), signs the CLI and the app with the hardened runtime, notarizes and staples the app, then packs it with an Applications link into a DMG that is signed, notarized and stapled too. See [Homebrew packaging](packaging/homebrew/README.md) and [app distribution](design-docs/user-qa/app-distribution.md).

## Design docs

Architecture, storage, agent integration, CLI and app UI designs are in [`design-docs/specs/`](design-docs/specs/).
