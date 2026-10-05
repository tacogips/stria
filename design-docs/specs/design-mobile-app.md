# iPhone and iPad App

## Status

Specified (implementation by Codex, reviewed in this repo).

## Goal

Stria runs on iPhone and iPad as well as the Mac, sharing `StriaCore` (the
SQLite page store, OCR, summaries, chats, search) and syncing libraries
through iCloud Drive (`design-icloud-sync.md`). On iOS and iPadOS the CLI
vendors that run local programs on a Mac (`claude-code`, `codex`, `cursor`)
cannot be selected; only API vendors (`openai`, `anthropic`, `gemini`,
`openrouter`, `cursor-api`) are offered.

## Build structure

- `Package.swift` adds `.iOS(.v17)`. `StriaCore` builds for iOS; the
  `stria` CLI and the macOS `stria-app` stay macOS executables.
- agent-gateway is pinned to the `ios-support` revision
  (`c68e1ffa3d7b1a20bbd8e5c8fb09e055b3f925fa`), whose library products build
  for iOS; process-based vendors fail there with `launchFailed(ENOTSUP)`.
- The mobile app lives in `Mobile/`: an XcodeGen spec `Mobile/project.yml`
  generating `Mobile/StriaMobile.xcodeproj` (generated, not committed), app
  sources in `Mobile/StriaMobile/`, `Info.plist` settings in the spec. The app
  target depends on the local package product `StriaCore`.
  - Bundle id `me.tacogips.stria.mobile`, display name "Stria", iOS 17+,
    iPhone and iPad (`TARGETED_DEVICE_FAMILY = 1,2`), all orientations on iPad.
  - Document types: PDF (`com.adobe.pdf`, role Viewer) and "Supports opening
    documents in place" off (imports copy the file).
- mise tasks: `ios:generate` (xcodegen), `ios:build` (xcodebuild for the
  iPhone and iPad simulators with `CODE_SIGNING_ALLOWED=NO`).

## Platform rules in StriaCore

- `KnownVendors.isAvailableOnThisPlatform(_:)`: false for `cliVendors` on
  every platform except macOS. `KnownVendors.selectable` lists the vendors a
  picker offers on this platform (on iOS the API vendors; on macOS all).
- Settings pickers (OCR, page summaries), the chat composer's vendor menu and
  `AgentPaneViewModel.availability(of:)` use it: on iOS a CLI vendor is not
  listed; if `config.json` names one (for example after copying a config),
  it shows as unavailable with "Runs a local CLI; only available on the Mac",
  and preflight fails with `serviceUnavailable` before any call.
- `LoginEnvironment` (login-shell import with `Process`) is macOS only.
- API keys on iOS: there is no login shell, so the key variable names in
  Settings cannot be filled from the environment. iOS Settings stores each
  API vendor's key in the Keychain (`SecItem`, service
  `me.tacogips.stria.apikey`, account = vendor) and the services read it from
  there; config still stores only names, never values. macOS keeps using
  environment variables.
- Data root on iOS: `Application Support/Stria` in the app container
  (`StriaPaths.defaultRoot`), excluded from iCloud backup for the cache.

## UI (SwiftUI, `Mobile/StriaMobile`)

Follows the Mac app's structure and flat style, with iOS idioms:

- Library: `NavigationSplitView` on iPad (library list in the sidebar, reader
  in the detail), `NavigationStack` on iPhone. Rows with the first-page
  thumbnail, title, OCR and summary badges; swipe to remove (confirmation);
  "+" imports PDFs with `fileImporter` (multiple); search field runs the OCR
  search across PDFs (results with page thumbnails and highlighted context;
  tapping opens the page).
- Reader: `PDFView` (UIViewRepresentable) with continuous vertical scroll,
  page indicator "n / N", go to page, and a toolbar with: Contents
  (outline + thumbnails as a sheet), Run OCR (the page-range sheet), and the
  agent. On iPad the agent pane is a trailing column (inspector) that can be
  shown or hidden; on iPhone it is a sheet with detents.
- Agent pane: the same three tabs as the Mac (Chat, History, Summary) built
  on `AgentPaneViewModel`, `LibraryViewModel` and the summary APIs: chat
  title bar with regenerate, transcript with page citation links, composer
  with the vendor/model menu (API vendors only), history list with titles and
  summaries, Summary tab with tags (tap to search), coverage, progress,
  Cancel and the summary run sheet.
- Settings (a sheet from the library toolbar): OCR (vendor, model, retries,
  auto-run, prompt with reset), Page Summaries (vendor, model, language,
  auto-run, prompt with reset), API keys (Keychain), System Prompt, iCloud
  Sync (`design-icloud-sync.md#settings`), Appearance.
- Shared SwiftUI pieces that do not depend on AppKit (`FlowLayout`,
  `PageRangeChoices`, `OCRRunSheet`, `SummaryRunSheet`, `Flat`) may move to a
  small cross-platform library target `StriaUI` used by both apps; AppKit-only
  views stay in `StriaApp`.

## Verification

- `swift build` / `swift test` / `swiftlint` on macOS stay green.
- `mise run ios:build` builds for an iPhone and an iPad simulator.
- The app launches in the iPhone 17 and an iPad simulator: library empty
  state, import of a sample PDF (via `simctl` adding it to Files or a debug
  launch argument that imports a bundled sample), the reader, the agent pane,
  and Settings with CLI vendors absent.
