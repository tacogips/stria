# App UI (StriaApp)

## Status

Implemented (stria v0.1). The layout follows existing macOS PDF readers instead of
inventing new patterns. See [References](#references).

## Scope

`StriaApp` (product `stria-app`) contains only SwiftUI views, the PDFKit
`NSViewRepresentable` wrapper, menu commands and app startup. All state and
behaviour live in `StriaCore/AppModel/` view models (`@MainActor`,
`@Observable`), so `swift test` covers them with fakes.

The app runs as a SwiftPM executable with no bundle. Startup therefore calls
`NSApplication.shared.setActivationPolicy(.regular)` and activates the app, so
it gets a Dock icon, a menu bar and keyboard focus. The data root comes from
`STRIA_HOME` or the default. The app has no `--home` flag.

## Window Structure

There is a single `WindowGroup` with a minimum size of 1100 x 700. `AppModel`
holds `route: .library | .reader(docId)`, and the root view switches between
two screens:

1. **Library** (home): `LibraryView`.
2. **Reader**, laid out as
   `NavigationSplitView(sidebar: LeftPane, detail: PDFPane)` with
   `.inspector(isPresented:)` for the agent pane.

The sidebar column resizes between 180 and 640 points and the inspector
between 300 and 720, so either pane can be made wide enough for long outlines
or answers.

The reader toolbar contains:

- leading: the built-in sidebar toggle (no second one is added), and a
  "< Library" back button that returns home (also `Esc`, `Cmd-Shift-L` via
  the View menu, and a "< Library" row at the top of the left pane);
- principal: a page field showing `n of N` with previous and next buttons;
- trailing: a `.searchable(placement: .toolbar)` search field and an
  inspector toggle button.

## Library (home)

- A `List` of imported documents (inset style with alternating row
  backgrounds; the row under the pointer is highlighted). Rows are ordered by
  most recent use: `COALESCE(last_opened_at, imported_at)` descending, so a
  new import appears at the top until something else is opened. Each row
  shows a document icon, the title, when it was last opened, the page count,
  and import or OCR progress: `Rendering 12/80`, `OCR 40/80`, the failed count,
  or the OCR `unavailable` reason, plus a small spinner while this app
  process is rendering or OCRing the document (`LibraryRow.isBusy`). Rows are ordered by `last_opened_at`
  descending, then `imported_at` descending.
- The toolbar search field runs the shared OCR search across every document
  (`LibraryViewModel.submitSearch`); the results replace the list, each row
  showing the title, page and snippet, and a click opens that document at
  that page (`AppModel.open(documentId:page:)`). Clearing the field returns
  to the list.
- Import uses a toolbar "Import" button (`Cmd-O`) that opens `fileImporter`
  (`UTType.pdf`, multiple selection), or PDF file URLs dropped onto the list.
  - Each import runs in the background through `StriaLibrary.importDocument`
    and streams `ImportEvent`s into its row.
  - A row can be opened as soon as `copied(docId)` arrives. Reading uses the
    original file, so it never waits for rendering or OCR.
  - Importing the same file again selects the existing row.
- The library has two modes, chosen with a segmented control in the toolbar
  and remembered in `UserDefaults` (`libraryViewMode`): **List** rows with a
  44 x 58 first-page thumbnail at the left, and **Cards**, an adaptive grid
  of 180-220 point cards with a 164 x 212 first-page image, the title, page
  count and status. Thumbnails are the stored first page decoded and
  downscaled (`StriaLibrary.firstPageThumbnail`, longest side 320 px),
  loaded on demand and cached in `LibraryViewModel.thumbnails`; a document
  still rendering shows a placeholder and loads when it becomes ready.
- To open a document, click its row or card once (or select it and press
  Return).
  The route switches to the reader first (its "Opening document" indicator
  shows), the `PDFDocument` is parsed off the main actor, `last_opened_at`
  is set, and background cache expansion of all pages starts. A failed open
  returns to the library with the error.
- Row context menu: "Run OCR" (pending pages), "Retry Failed OCR" and
  "Remove..." (also the Delete key on the selected row). Removal asks for
  confirmation, names what is deleted (stored copy, page images, OCR text,
  chat history) and states that the imported file itself is untouched. It
  calls `StriaLibrary.removeDocument` (`design-storage.md#document-removal`).
- Import errors (`invalidPDF`, IO) appear in an alert. A failed copy leaves
  no row in the list.
- An empty library shows the import button and a drop hint as an overlay
  (not a list row). The window title is "Library"; the reader's title is the
  document title.

## Reader: Left Pane (sidebar)

A segmented picker at the top switches between **Contents** and
**Thumbnails**. A third segment, **Search**, appears (and is selected) only
while a search is active.

- **Contents**: a tree from `outline_json`. While the document is still
  `rendering`, the tree comes from the `OutlineExtractor` running on the open
  `PDFDocument`. Clicking a node with a page navigates to it; nodes without a
  page are not clickable. The current section is the list selection: it is
  the last node, in document order, whose page is at or before the current
  page. Its collapsed ancestors are expanded and the row is scrolled into
  view, as in Preview. Rows come from `ReaderViewModel.outlineRows`
  (`OutlineRow`, built once per open). If the PDF has no outline, the mode
  shows the flat list "Page 1 ... Page N" with the current page selected.
- **Thumbnails**: a lazy list of page thumbnails rendered from the open
  `PDFDocument` (`PDFPage.thumbnail(of:for:)`) for visible rows only, off the
  main actor so scanned pages do not stutter the sidebar, each labelled with
  its page number. The current page is highlighted and kept
  scrolled into view. Clicking a thumbnail navigates to that page.
- **Search**: submitting the toolbar search field (Return) runs the shared
  OCR search scoped to the open document (`design-storage.md#search`). The
  results replace the previous mode. Each row shows the page number and the
  snippet; clicking a row navigates to that page. When some pages are not yet
  OCRed, a footer reads "N pages not yet OCRed". A failed search shows its
  error in the pane (`ReaderViewModel.searchError`). Clearing the search
  field returns to the previous mode.

## Reader: Center Pane (PDF)

- The `PDFView` wrapper uses `displayMode = .singlePageContinuous`,
  `displayDirection = .vertical` and `autoScales = true`. The document is
  loaded from `originals/<docId>.pdf`. Continuous scrolling is the only mode,
  so there is no paging mode.
- Current page tracking: `.PDFViewPageChanged` updates
  `ReaderViewModel.currentPage` (1-based).
- Programmatic navigation (outline, thumbnail, search result, citation chip,
  history entry, page field, Go to Page) sets
  `ReaderViewModel.navigation` to a `PageNavigation {id, page}` with a fresh
  id. The wrapper's coordinator remembers the last handled id and calls
  `go(to:)` once per id, so repeated requests for the same page work and no
  observable state is mutated during a SwiftUI update (which would otherwise
  trigger feedback loops and runtime warnings). `requestedPage` is a
  read-only view of `navigation?.page`. A request is held until the
  `PDFView` is in a window with a non-zero layout, because `go(to:)` before
  the first layout pass of an `autoScales` view is reset by that pass; this
  is what makes the last-read restore land on the right page.
- Zoom: View > Zoom In / Zoom Out / Actual Size / Zoom to Fit
  (`Cmd-+`, `Cmd--`, `Cmd-0`, `Cmd-9`) go through `ReaderViewModel.zoom`
  (`ZoomRequest`, consumed once per id like navigation).
- Page jump works three ways:
  - the toolbar `n of N` field, committed with Return. The field keeps its
    own text while focused, so scrolling never overwrites what is being
    typed; it re-syncs from the current page when focus leaves;
  - Go > Go to Page... (`Cmd-Opt-G`), which opens a small sheet with a number
    field;
  - Go > Next Page and Previous Page (`Cmd-Opt-Down` / `Cmd-Opt-Up`) and the
    toolbar buttons.
  Non-numeric input is discarded, and numbers are clamped to `1...pageCount`.
- Last-read restore: page changes are saved to `documents.last_read_page`,
  debounced to 1 s and flushed when leaving the reader. On open, the reader
  goes to `last_read_page`, or page 1.
- On open, `ReaderViewModel.open(docId)` also starts background expansion of
  all page images into the PNG cache. Expansion is cancelled when you switch
  documents, and these PNGs are never displayed.

## Reader: Right Inspector (agent pane)

- Visibility: `.inspector(isPresented:)`, toggled from the toolbar button or
  View > Show Agent (`Cmd-Opt-0`). The width can be adjusted, and the pane
  is shown by default the first time.
- Scope picker: "This page", "Nearby pages" or "Whole PDF"
  (`design-agent-integration.md#ask`). A scope indicator line below it states
  what the assistant will see, for example "Sees page 12",
  "Sees pages 11-13", or "Sees up to 4 relevant pages of <title>, including
  page 12".
- Transcript: the active thread's messages as chat bubbles: the user's
  questions on the right in the accent colour, the assistant's answers (and
  the streaming bubble) on the left.
  - Every `[<docId> p.<page>]` marker that matches the open document is
    rendered inline as a `p. <page>` link that navigates the PDF to that
    page (an `AttributedString` link with a `stria-page://` URL handled by
    `openURL`). Markers for other documents stay plain text.
  - The question appears in the transcript as soon as it is sent (a
    provisional record with `AgentPaneViewModel.pendingMessageID`); the
    persisted records replace it when the answer arrives, and it is removed
    if the request is cancelled or unavailable.
  - Failed answers appear as error messages, and they are persisted.
- Suggested questions: an empty thread shows three fixed prompts: "Summarize
  this page", "Explain the key terms on this page" and "What should I read
  next to understand this?". Clicking one sends it.
- Input: a multi-line text field. Send with the Send button or
  `Cmd-Return`. During the request an assistant bubble with a small
  progress indicator shows the answer as it streams
  (`AgentPaneViewModel.streamingAnswer`); when the answer completes, the
  bubble is replaced by the persisted transcript message. The Send button
  becomes Cancel (`Cmd-.`, also Agent > Cancel Question) while a request is
  in flight; cancelling stops the gateway turn and persists nothing. "New Chat" starts a new thread. A thread
  is anchored to the page that was current at its first question.
- `unavailable` errors (for example, a credential env var is unset) show an
  inline notice naming the reason and are not persisted.
- The pane has two tabs, **Chat** and **History**, as a segmented control
  pinned at the top (the content below is top-aligned, so switching tabs
  never moves the control). Chat holds the scope picker, transcript and composer. History
  fills the pane with the past questions and answers; its own segmented
  control switches between "This page" and "This PDF"
  (`design-storage.md#chat-history-queries`), each row shows the role, page,
  relative time and up to three lines of text, and an empty state names the
  scope. The list refreshes when the tab is shown, after each answer, and on
  page change debounced by 300 ms (and only in "This page" mode, where the
  result can change). Selecting an entry reopens its thread in the Chat tab
  and jumps to its page. Selecting an entry opens its thread and jumps
  to its anchor page.

## Visual Style and Appearance

Flat and solid: no corner radius and no translucent fills anywhere in the
app (`Flat` in `StriaApp`). Chat bubbles are square, the user's in the
solid accent colour with white text and the assistant's in the control
background colour; text fields are square with a 1-point separator-colour
border (`FlatTextFieldStyle`); hover and selection use the system's solid
selection colours; the setup banner is a solid control-background strip.
Every fill is an opaque system colour, so both modes stay readable.

Appearance is an app-wide choice (`Appearance`: light, dark, system) stored
in `UserDefaults` under `appearance`. **Light is the default.** It is set
from Settings > Appearance, View > Appearance, or toggled with
`Cmd-Shift-D` (menu) and `Shift+D` (reader shortcut, as in chilla); the
scenes apply it with `preferredColorScheme`.

## Settings Window

`Settings` scene (`Cmd-,`), backed by `SettingsViewModel` in
`StriaCore/AppModel`, which holds a draft of the configuration and writes it
with `StriaLibrary.saveConfig` on Save (nothing is written before). Sections:

- OCR: vendor picker ("Not configured", "PDF text layer", then the gateway
  vendors with display names), model field (shown for model vendors, with the
  vendor's suggested model as placeholder), API key environment variable
  field (API vendors only), "Run OCR automatically after import" toggle, and
  the concurrency stepper. Choosing a vendor fills empty model and variable
  fields with suggestions.
- Agent: vendor, model and API key variable in the same way.
- System Prompt: a text editor showing the current prompt (the default when
  none is set) with "Reset to Default". A prompt equal to the default is
  stored as null.
- Save validates (a model vendor needs a model, an API vendor needs a
  variable name) and shows the error inline; Revert reloads the file.

After a save, `AppModel.configRevision` increments; the library banner and
the agent pane's "No agent vendor is configured" notice (both with a
`SettingsLink`) re-evaluate. Until both vendors are set, the library shows a
banner pointing to Settings, rows with pending pages read "OCR not run:
choose a vendor in Settings, then Run OCR", and the Run OCR toolbar button is
disabled. The app name shown in the menu bar and Dock is "Stria", from the
Info.plist embedded in the executable (`Resources/StriaInfo.plist`).

## Reader Shortcuts

Single-key shortcuts in the style of chilla (`ReaderShortcut`, a local
`NSEvent` monitor installed while the reader is on screen). They never fire
while a text field or text view has focus, so typing is never interrupted:

| Keys | Action |
| --- | --- |
| `Esc` | Back to the library (unless a sheet is open) |
| `Shift+L` | Collapse or expand the left pane |
| `Shift+R` | Collapse or expand the agent pane |
| `/` | Show the agent pane and focus its input |
| `Ctrl+D` / `Ctrl+U` | Page the PDF down / up (`PDFView.scrollPageDown/Up`) |
| `j` / `k` | Scroll the PDF one line down / up |
| `Shift+D` | Toggle light and dark mode |
| `?` | Show the shortcut list (also Help > Keyboard Shortcuts, `Cmd-/`) |

Scroll requests travel like navigation and zoom: `ReaderViewModel.scroll`
(`ScrollRequest`, consumed once per id by the `PDFView` coordinator). The
input focus request is `AgentPaneViewModel.focusInputRequest`.

## Commands and Shortcuts

Menu commands reach the focused reader through `focusedSceneValue(\.reader)`.
Commands are disabled when no reader is focused.

| Menu | Item | Shortcut |
| --- | --- | --- |
| File | Import PDF... | `Cmd-O` |
| View | Show/Hide Sidebar (built-in `SidebarCommands`) | `Ctrl-Cmd-S` |
| View | Show/Hide Agent | `Cmd-Opt-0` |
| View | Library | `Cmd-Shift-L` |
| Go | Go to Page... | `Cmd-Opt-G` |
| Go | Next Page / Previous Page | `Cmd-Opt-Down` / `Cmd-Opt-Up` |
| View | Zoom In / Zoom Out / Actual Size / Zoom to Fit | `Cmd-+` / `Cmd--` / `Cmd-0` / `Cmd-9` |
| Agent | Send | `Cmd-Return` (in the input field) |
| Agent | New Chat | `Cmd-Shift-N` |
| Agent | Cancel Question | `Cmd-.` |

Every shortcut is declared once, on the menu command. Toolbar buttons call
the same action without a shortcut of their own, so a key press never fires
twice (which would, for example, toggle the inspector off and on again).

## View Models (StriaCore/AppModel)

| Type | State | Tested behaviour |
| --- | --- | --- |
| `AppModel` | route, library, current reader | open routes to the reader and updates `last_opened_at`; back to library flushes the reading position |
| `LibraryViewModel` | documents, per-document progress, alert | import events update rows; idempotent re-import selects the existing doc; OCR actions call the coordinator with the right selection; recents ordering |
| `ReaderViewModel` | document, pageCount, currentPage, requestedPage, outline, currentOutlineNode, sidebarMode, searchResults, pageFieldText | jump parsing and clamping; next and previous bounds; current outline node; outline fallback; search mode enter and exit; last-read save and restore; open starts cache expansion and switching cancels it |
| `AgentPaneViewModel` | scope, scopeDescription, input, transcript, inFlight, historyMode, history, notice | context pages per scope; scope indicator text; citation chip parsing; send persists via `FakeAgentService`; failed vs unavailable handling; history reload per mode and page |

Visual details such as scroll smoothness, layout and thumbnail appearance
are verified manually with `swift run stria-app`.

## References

Patterns adopted from existing readers:

| Reader | Pattern adopted | Where in stria |
| --- | --- | --- |
| Apple Preview | Sidebar with a mode switcher (Table of Contents / Thumbnails); continuous scroll; Go > Go to Page (`Cmd-Opt-G`) as a small sheet; toolbar search field whose results list in the sidebar with page numbers; sidebar toggle in the toolbar | Left pane segmented modes, Search mode, Go menu, toolbar layout |
| Skim (open-source macOS PDF reader) | Left pane segmented TOC / Thumbnails; search results temporarily replace the TOC in the left pane; a collapsible right side pane; toolbar page field showing `n of N` with previous and next; remembering the last-read page per document | Search mode replacing Contents until cleared; `n of N` field; `last_read_page` restore; collapsible inspector |
| PDF Expert for Mac | Library / recents home showing previously opened documents; left sidebar tabs (Outline / Thumbnails / Search); minimal toolbar | Library home ordered by `last_opened_at`; three sidebar modes; small toolbar |
| Adobe Acrobat AI Assistant pane, Zotero 7 reader side pane | Right-side chat pane with suggested questions; answers cite pages as clickable chips that scroll the PDF; a scope indicator for what the assistant sees | Agent inspector: suggested questions, citation chips, scope picker and indicator |
| macOS 14 SwiftUI conventions (Xcode, Keynote, Preview inspectors) | `NavigationSplitView` sidebar plus `.inspector(isPresented:)` for the right pane; toolbar toggle buttons for both panes; `CommandMenu` and keyboard shortcuts through `focusedSceneValue`; `.searchable` in the toolbar | Reader window structure, Commands and Shortcuts table |

Patterns deliberately not adopted in v0.1, because no accepted requirement
needs them: annotation and highlight tools (Skim, PDF Expert), tabs and
multiple windows per document (Preview, PDF Expert), and single-page or
two-up display modes (Preview).
