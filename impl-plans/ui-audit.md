# UI audit and compact window support

Scope: audit every app view for duplicate controls, broken layout and usability;
include the user-reported AeroSpace width constraint, rounded left pane and
excess whitespace in the agent header.

## Changes

- Separate 1100 x 700 preferred launch size from 320 x 240 minimum content size,
  following chilla's compact tiling approach and retaining standard window controls.
- Replace native rounded sidebar/inspector containers with a flat HSplitView.
- Use compact pane sheets below 760/1000 points and a compact toolbar below 540.
  Match menu and single-key pane actions to the visible presentation.
- Keep Library navigation available independently of the sidebar. Remove the
  redundant collapsed-sidebar edge button and empty-library Import action.
- Group agent tabs and New Chat together, tighten header and scope spacing,
  and prevent child pane titles from replacing the document window title.
- Let vendor/model controls fit narrow panes; bound composer height and wrap warnings.
- Fix the saved long-conversation sheet layout hang with eager transcript layout,
  wrapped message text and immediate scrolling after transcript updates.
- Select library rows/cards with one click and open with double-click or Return;
  visibly mark selected cards. Stack row metadata so titles stay readable.
- Remove empty zebra stripes from library/search lists, duplicate search controls,
  repeated model wording in OCR confirmation, and OCR actions on search results.
- Make search and shortcut sheets flexible; scroll shortcut help at small heights.
- Correct toolbar accessibility containment and labels, and disable New Chat
  menu/suggestion actions while requests are in flight or unavailable.
- Keep import error alerts visible in the reader as well as the library.
- Pause single-key shortcuts during native menu tracking; handle initial composer
  focus when the agent pane is opened as a compact sheet.
- Correct the API/CLI prompt test fixture to explicitly use the OpenAI API vendor.
  The shared fixture defaults to Claude Code and previously made both cases CLI.

## Verification

Runtime checks use `/tmp/StriaUIAudit.app` with `/tmp/stria-ui-audit`, isolated
from the user's library. The fixture has three embedded-text PDF pages, local
PDF-text-layer OCR and seeded sample history, including long and error answers.
No external agent request is needed for these checks.

Verified states so far:

- Empty library and setup banner; populated list/card modes and card selection.
- OCR toolbar selection and confirmation, import file picker, OCR search results.
- Native tiled reader at 628 and 417 logical points, plus a 1280-point fullscreen
  three-pane layout. The former 1100-point minimum clipped the narrow tile.
- Compact contents and thumbnails sheets, chat and populated history sheets.
- Long history answer opens, wraps and scrolls without the reproduced sizing hang.
- Settings grouped form and pinned Save/Revert footer.

Additional verified states:

- Final compact library toolbar at 417 points: List/Cards, Search, OCR and Import
  visible together, with distinct accessibility labels.
- Final compact reader toolbar: Library, sidebar, page number and agent visible
  together, with distinct accessibility labels.
- Go to Page sheet navigates to page 3; the toolbar and selection reflect it.
- Shortcut help scrolls and Escape dismisses it.
- Light/dark library, wide flat reader and compact composer. Vendor/model controls
  fit; `i` opens the compact composer with keyboard focus.
- Escape dismisses a vendor menu while leaving the compact agent sheet open.

## Remaining final verification

Computer Use began returning `cgWindowNotFound` for the audit app, the installed
Stria app and Finder. An environment-gated window manifest now distinguishes
an empty window list from a capture failure. The isolated audit app initially
had no windows. Launching it with `-ApplePersistenceIgnoreState YES` creates a
visible Library window without modifying its existing saved state. However,
Computer Use still cannot access that window and its offscreen layer render
contains only toolbar chrome. A stable scene identifier did not resolve the
failure, so that experiment was reverted; production launch policy is unchanged.

The final source keeps the existing library alert and adds its equivalent to
ReaderView. Runtime verification of reader import errors and the solid sidebar
list background remains pending. On the third consecutive goal turn, the test
process was confirmed live and the manifest still reported a visible Library
window, while Computer Use again returned `cgWindowNotFound` for its exact
bundle identifier. Source review confirmed the reader alert uses the same
library error binding as the existing library alert, and the plain sidebar
list reveals the opaque parent panel background; these are insufficient to
prove final visual behavior. The goal is blocked on window access; do not
claim full audit completion from the earlier screenshots. The isolated audit
process was stopped after this check; the installed app remains untouched.

Final checks after all current source edits passed:

- `mise exec -- swift build --product stria-app`
- `mise exec -- swiftlint`: 0 violations across 150 files.
- `mise exec -- swiftlint --quiet`: passed after adding the window manifest.
- `mise exec -- swift test`: 165 tests across 47 suites passed.
- `git diff --check`

Logs are `/tmp/stria-ui-build.log`, `/tmp/stria-ui-lint.log`, and
`/tmp/stria-ui-tests.log`. The installed application was not replaced.
