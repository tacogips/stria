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

There is a single `WindowGroup` with a preferred launch size of 1100 x 700
and a minimum content size of 320 x 240. Preferred size does not constrain
AeroSpace tiles. Standard native close, minimize and fullscreen controls remain.
`AppModel` holds `route: .library | .reader(docId)`.

The reader uses a flat `HSplitView`: contents/thumbnails, PDF, and agent.
There is no native rounded sidebar or inspector container. The sidebar resizes
from 180 to 400 points and the agent from 300 to 600. Below 760 points the
sidebar opens as a sheet; below 1000 points the agent opens as a sheet. Their
wide-window visibility preferences survive resizing. Sheets have a Done button;
short agent sheets scroll their content so the composer remains reachable.

The reader toolbar has one Library button, one sidebar toggle, a page field,
and one agent toggle. The Library button remains available when the sidebar
is hidden. Below 540 points these controls share a compact group; the page
field shows `n / N`, and previous/next remain available through menu shortcuts.
Child panes do not set the window title. The agent header groups Chat/History,
New Chat and Resume Previous Chat on the left; when the open chat started on a
page of this PDF, a flag button labelled `p.N` on the right jumps back to it.

Wide-window pane widths persist across launches (`readerLeftPaneWidth`,
`readerAgentPaneWidth` in `UserDefaults`, defaults 240 and 360 points).
`SplitWidthKeeper` finds the `NSSplitView` behind the `HSplitView`, saves a
width only while the user drags a divider (the current event is a left-mouse
drag in that window), and moves the dividers back to the saved widths after
any other resize (window resize, tiling, a pane shown again), so the PDF takes
the remaining width.

## Library (home)

- A `List` of imported documents (inset style; the row under the pointer is highlighted). Rows are ordered by
  most recent use: `COALESCE(last_opened_at, imported_at)` descending, so a
  new import appears at the top until something else is opened. Each row
  shows a document icon, the title, when it was last opened, the page count,
  and import or OCR progress: `Rendering 12/80`, `OCR 40/80`, the failed count,
  or the OCR `unavailable` reason, plus a small spinner while this app
  process is rendering or OCRing the document (`LibraryRow.isBusy`). Rows are ordered by `last_opened_at`
  descending, then `imported_at` descending.
- OCR search across every document opens with `/` or `Cmd-F`
  ([OCR Search](#ocr-search)); its results replace the list until Esc.
- The library toolbar uses native controls only, so the system sizes their
  capsules: a List / Cards segmented control at the leading edge, the title
  "Library" with the document count as subtitle, and at the trailing edge
  Search (opens the OCR search popup), Run OCR, and a labelled
  "+ Import PDF" button. The empty-library message shows in both modes.
- Import uses the toolbar "Import PDF" button (`Cmd-O`) that opens `fileImporter`
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
- To open a document, click its row or card once (or select it with the
  arrow keys and press Return). The last opened document stays selected for
  the toolbar Run OCR button and the Delete key; selected cards have an
  accent border. Card accessibility activation also opens the document.
  The route switches to the reader first (its "Opening document" indicator
  shows), the `PDFDocument` is parsed off the main actor, `last_opened_at`
  is set, and background cache expansion of all pages starts. A failed open
  returns to the library with the error.
- Each row and card shows an OCR badge for documents that finished
  rendering: "OCR done" (green), "OCR n/N" (partial, blue), "Not OCRed"
  (grey) or "OCR n failed" (orange), with a tooltip giving the counts
  (`LibraryRow.ocrState`).
- Row context menu: "Run OCR..." and "Remove..." (also the Delete key on
  the selected row). Run OCR (context menu, library toolbar button for the
  selected document, reader toolbar button, File > Run OCR..., `Cmd-Shift-O`)
  opens `OCRRunSheet`, which is the confirmation: radio choices "Remaining
  pages" (pending and failed; preselected when any), "All N pages" and
  "Pages" with a page-list field ("1-3, 8"; spaces allowed;
  `OCRRange.pages`, parsed by `PageListParser`). In the reader the field is
  prefilled with the current page and preselected. The sheet names the page
  count, the OCR vendor and model, and that existing text on chosen pages is
  replaced; an invalid list shows the reason and disables Run OCR. While a
  run is in progress the reader's OCR button shows a spinner. Removal asks for
  confirmation, names what is deleted (stored copy, page images, OCR text,
  chat history) and states that the imported file itself is untouched. It
  calls `StriaLibrary.removeDocument` (`design-storage.md#document-removal`).
- Import errors (`invalidPDF`, IO) appear in an alert in either the library or reader. A failed copy leaves
  no row in the list.
- An empty library shows the import button and a drop hint as an overlay
  (not a list row). The window title is "Library"; the reader's title is the
  document title.

## Reader: Left Pane (sidebar)

An icon control at the top switches between **Contents** and
**Thumbnails**. OCR search is not in the sidebar (see
[OCR Search](#ocr-search)).

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

## OCR Search

There is no always-visible search field. Edit > Search OCR Text…
(`Cmd-F`) or the `/` key (library and reader, paused while typing) opens a
popup (`SearchPrompt`) with the query field and, in the reader, a scope
control: this PDF (default) or all PDFs. Return searches.

Results replace the center pane (`SearchResultsView`; in the reader an
overlay above the PDF, which keeps its scroll position): a header with a
back icon, the query in quotes and "N pages in <title> / in all PDFs", then
one row per page with the page thumbnail (`StriaLibrary.pageThumbnail`,
downscaled stored image), the document title in all-PDF searches, the page
number, and the text around the hit with every matched term in the find
highlight colour (`SearchContextBuilder`, built from the page's normalized
OCR text so wrapped Japanese terms are found; the index snippet is the
fallback). Clicking a row opens that page (jumping within the open PDF or
opening the other document). Esc or the back icon returns to the previous
screen; in the reader Esc closes results before it would leave for the
library. One `SearchViewModel` (on `AppModel`) serves both screens.

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

- Visibility: the flat split pane or compact sheet, toggled from the toolbar button or
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
- Input: a rounded box spanning the pane (a text editor, 96 points high;
  Return inserts a new line). Along its bottom edge sit the vendor menu and
  model picker, stacked to fit narrow panes, and the
  send button (an up-arrow; `Cmd-Return`), which becomes a stop button
  while an answer is in flight. A warning with an Open Settings link
  appears above the box when the selected vendor lacks its key. During the request an assistant bubble with a small
  progress indicator shows the answer as it streams
  (`AgentPaneViewModel.streamingAnswer`); when the answer completes, the
  bubble is replaced by the persisted transcript message. The Send button
  becomes Cancel (`Cmd-.`, also Agent > Cancel Question) while a request is
  in flight; cancelling stops the gateway turn and persists nothing. "New Chat" starts a new thread. A thread
  is anchored to the page that was current at its first question.
- `unavailable` errors (for example, a credential env var is unset) show an
  inline notice naming the reason and are not persisted.
- The pane has three tabs, **Chat**, **History** and **Summary** (the
  current page's summary, `design-page-summaries.md#app`), as a segmented control
  pinned at the top (the content below is top-aligned, so switching tabs
  never moves the control). Chat holds a title bar, the scope picker,
  transcript and composer (no suggested questions). The title bar shows the
  open chat's title (`AgentPaneViewModel.chatTitle`: the AI title, else the
  first question's first line, else "New Chat" in secondary colour), a
  "wand.and.stars" button that asks the AI for a new title (a spinner while
  it runs; disabled for a new chat or without a vendor), and the `p.N` flag
  button for the chat's start page. History lists conversations, not
  messages; its own segmented control switches between "This page" and
  "This PDF" (`design-storage.md#thread-overviews`). Each row shows the page,
  message count, relative time, the title, the conversation summary (up to four lines;
  "Summarizing..." while one is written; a stale icon when newer messages
  exist) and the first question in two secondary lines. The context menu
  offers Summarize / Summarize Again and Write Title / Write New Title. The list refreshes when the tab is
  shown, after each answer, and on page change debounced by 300 ms (only in
  "This page" mode). Selecting a row reopens its thread in the Chat tab and
  jumps to its anchor page.
- Summaries: with `agent.autoSummarize` (default true; Settings toggle
  "Title and summarize conversations after each answer") the first successful
  answer of a conversation also writes its title, then each answer starts
  a background `ThreadSummarizer` call with the composer's vendor and model
  (`design-agent-integration.md#conversation-summaries`). A failure shows a
  notice and keeps the previous summary.
- Resume Previous Chat (`r`, `Cmd-Shift-R`, header button) reopens the most
  recently updated conversation about this PDF from a new chat, and each
  older one on repeated use; it jumps to that chat's anchor page and focuses
  the input. With none left it shows "No earlier/older conversation about
  this PDF." Go to Chat Start Page (`s`, `Cmd-Shift-J`, flag button) jumps
  to the page of the open chat's first question.

## Visual Style and Appearance

Flat and solid: no translucent fills, and no corner radius except on chat
bubbles (`Flat` in `StriaApp`). Chat bubbles have a 10-point radius and the
control background colour; the user's is outlined in the accent colour
(not filled, so the text stays easy to read) and the assistant's in the
separator colour; text fields are square with a 1-point separator-colour
border (`FlatTextFieldStyle`); hover and selection use the system's solid
selection colours; the setup banner is a solid control-background strip.
Every fill is an opaque system colour, so both modes stay readable.

Appearance is an app-wide choice (`Appearance`: light, dark, system) stored
in `UserDefaults` under `appearance`. **Light is the default.** It is set
from Settings > Appearance, View > Appearance, or toggled with
`Cmd-Shift-D` (menu) and `Shift+D` (reader shortcut, as in chilla); the
scenes apply it with `preferredColorScheme`.

Mode switches are icon-only (`IconSegmentedControl`): sidebar Contents /
Thumbnails / Search, agent pane Chat / History, scope This page / Nearby
pages / Whole PDF, history This page / This PDF, and library List / Cards.
Each segment is its own button so it has its own hover description; the
selected one is a solid accent square. Back to Library, New Chat, Send and
Cancel are icons with tooltips as well.

## Settings Window

`Settings` scene (`Cmd-,`, also Agent > Settings…), backed by `SettingsViewModel` in
`StriaCore/AppModel`, which holds a draft of the configuration and writes it
with `StriaLibrary.saveConfig` on Save (nothing is written before). Sections:

- OCR: vendor picker ("Not configured", "PDF text layer", then the gateway
  vendors with display names), a model picker limited to that vendor's models
  (`ModelCatalog`, a table in code that follows konjac's catalog for its
  vendors; kept in code so the signed app needs no resource bundle; the first
  entry is the suggested default; plus models fetched live for API vendors through
  `GatewayModelCatalogService` with a "Fetch models from vendor" button, plus
  "Custom…" which reveals a free-text id field), API key environment variable
  field (API vendors only), "Run OCR automatically after import" toggle, and
  the concurrency stepper. Choosing a vendor fills empty model and variable
  fields with suggestions and clears a model the new vendor does not know, so
  a model id is never sent to the wrong vendor.
- Page Summaries: auto-run toggle, vendor, model, language picker and prompt
  template editor (`design-page-summaries.md#app`). The agent pane's third
  tab, Summary, shows the current page's summary with a redo sheet.
- OCR also has "Retries for a malformed reply" (`ocr.formatRetries`, 0...5)
  with a note on the JSON reply and the 2, 4, 8... second backoff. The Summary
  tab lists the page's OCR tags as bordered chips above the summary; clicking
  one searches every PDF for it.
- OCR Prompt: a text editor showing the prompt sent with each page image
  (`OCRDefaults.prompt` when `ocr.prompt` is null), "Using the default
  prompt." / "Custom prompt.", and Reset to Default. Saving text equal to the
  default stores null. Changes apply to the next OCR run.
- Agent: vendor, model and API key variable in the same way.
- System Prompt: a text editor showing the current prompt (the default when
  none is set) with "Reset to Default". A prompt equal to the default is
  stored as null.
- Save validates (a model vendor needs a model, an API vendor needs a
  variable name) and shows the error inline; Revert reloads the file. The
  sections scroll, and Save / Revert sit in a bar pinned below the form, so
  they stay reachable at any height; the window is resizable (minimum
  520 x 420).

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
| `Esc` | Close search results; otherwise back to the library (unless a sheet is open) |
| `Shift+L` | Collapse or expand the left pane |
| `Shift+R` | Collapse or expand the agent pane |
| `/` | Open the OCR search popup |
| `i` | Show the agent pane and focus its input (also `Cmd-L`) |
| `n` | Start a new chat and focus the input |
| `r` | Resume the previous chat about this PDF (repeat for older ones) |
| `s` | Go to the page where the open chat started |
| `Ctrl+D` / `Ctrl+U` | Page the PDF down / up (`PDFView.scrollPageDown/Up`) |
| `j` / `k` | Scroll the PDF one line down / up |
| `Shift+D` | Toggle light and dark mode |
| `?` | Show the shortcut list (also Help > Keyboard Shortcuts, `Cmd-/`) |

Scroll requests travel like navigation and zoom: `ReaderViewModel.scroll`
(`ScrollRequest`, consumed once per id by the `PDFView` coordinator). The
input focus request is `AgentPaneViewModel.focusInputRequest`.

## Commands and Shortcuts

Menu commands reach the focused reader through `focusedSceneValue(\.reader)`.
Commands are disabled when no reader is focused. The agent commands run the
same `ReaderShortcut` handler as the single keys (`striaReaderShortcut`), so
they also reveal a hidden agent pane. `Ctrl-M` is a local key monitor
(`ControlMSendMonitor`) that sends only while the chat input has focus.

| Menu | Item | Shortcut |
| --- | --- | --- |
| File | Import PDF... | `Cmd-O` |
| View | Show/Hide Sidebar | `Ctrl-Cmd-S` |
| View | Library as List / Library as Cards | `Cmd-1` / `Cmd-2` |
| File | Run OCR... (library: selected document; reader: this PDF) | `Cmd-Shift-O` |
| View | Show/Hide Agent | `Cmd-Opt-0` |
| View | Library | `Cmd-Shift-L` |
| Go | Go to Page... | `Cmd-Opt-G` |
| Go | Next Page / Previous Page | `Cmd-Opt-Down` / `Cmd-Opt-Up` |
| View | Zoom In / Zoom Out / Actual Size / Zoom to Fit | `Cmd-+` / `Cmd--` / `Cmd-0` / `Cmd-9` |
| Agent | Settings… (opens the Settings window, OCR and agent vendors) | `Cmd-Shift-,` |
| Agent | Send | `Cmd-Return` or `Ctrl-M` (in the input field) |
| Agent | Focus Chat Input | `Cmd-L` |
| Agent | New Chat | `Cmd-Shift-N` |
| Agent | Resume Previous Chat | `Cmd-Shift-R` |
| Agent | Go to Chat Start Page | `Cmd-Shift-J` |
| Agent | Cancel Question | `Cmd-.` |

Every shortcut is declared once, on the menu command. Toolbar buttons call
the same action without a shortcut of their own, so a key press never fires
twice (which would, for example, toggle the inspector off and on again).
Every toolbar button's tooltip (`.help`) names its shortcut, for example
"Hide the sidebar (Ctrl-Cmd-S or Shift+L)".

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
