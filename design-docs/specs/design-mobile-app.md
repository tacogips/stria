# iPhone and iPad App

## Status

Implemented in `Mobile/StriaMobile` with an XcodeGen app target and mise tasks.
Mac build and all 215 tests pass (serial execution); SwiftLint has zero violations.
StriaCore builds for iOS and all mobile sources pass iOS type checking.
The isolated simulator app compile/link build also passes for device families 1,2.
Full icon-enabled simulator builds and screenshots require an unrestricted
CoreSimulator session: this sandbox blocks the service and asset compiler's
runtime lookup. Xcode compiler macro subprocesses also need an unrestricted
sandbox; the isolated compile/link check uses `-disable-sandbox`.
Run `scripts/ios-simulator-screenshots.sh` outside the sandbox.

Implementation decisions/deviations:
- Mobile-specific SwiftUI pieces remain in the app target; no StriaUI target
  or Mac view changes were needed.
- iPad uses a flat trailing agent column controlled by the toolbar; iPhone
  uses a sheet with medium/large detents. Regular/compact size classes adapt
  navigation to multitasking as well as device size.
- API keys save/delete immediately; configuration saves explicitly. Folder
  selection stores its bookmark immediately and resolves it for every pass.
- Xcode runs from Mobile so its local package path resolves consistently.
  Dependencies are copied from resolved `.build` checkouts into Mobile/build;
  `.build` and Package.resolved are unchanged.
- With CoreSimulator blocked, ios:build attempts a generic simulator build;
  asset compilation can still fail because it requires simulator runtimes.
  An ignored validation project excludes the asset catalog and disables the
  compiler subprocess sandbox to validate the Swift app separately.
- DEBUG launch routes `-StriaReader`, `-StriaAgent`, `-StriaSettings`, and
  `-StriaOCRVendors` accompany `-StriaSampleImport` for reproducible captures.
- The default parallel macOS test run stalled in this environment; the full
  suite passed with `--no-parallel`. Native iCloud/Keychain and interactive
  simulator behavior still require device/simulator verification.

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

### Implementation verification (2026-10-05)

- `swift build --scratch-path Mobile/build/macos --cache-path Mobile/build/swift-cache --disable-sandbox --skip-update --disable-automatic-resolution`: passed.
- `swift test` with the same scratch/cache options and `--no-parallel`: all
  215 tests in 56 suites passed. The initial parallel run stalled and was stopped.
- `swiftlint lint --no-cache`: zero violations across 198 files.
- SwiftPM `StriaCore` build for `arm64-apple-ios17.0-simulator`: passed.
- iOS `swiftc -typecheck -disable-sandbox` for the mobile sources: passed.
- Xcode generic simulator compile/link check with the asset catalog excluded
  in `Mobile/build/compile.yml`, and `OTHER_SWIFT_FLAGS` adding
  `-disable-sandbox`: passed. This is validation only, not the shipping project.
- `mise run ios:build`: blocked by the sandbox's compiler macro subprocess
  restriction; a retry disabling that subprocess sandbox reaches asset
  compilation, which fails because CoreSimulator exposes no runtimes.
- `xcrun simctl list devices available`: blocked by CoreSimulator service
  access. No devices could be selected, installed, launched or captured here.

The screenshot script will create these files after it runs outside the sandbox
(they have not been captured in this run):

- `Mobile/build/screenshots/iphone-library.png`
- `Mobile/build/screenshots/iphone-reader.png`
- `Mobile/build/screenshots/iphone-agent-chat.png`
- `Mobile/build/screenshots/iphone-settings.png`
- `Mobile/build/screenshots/iphone-settings-ocr-vendors.png`
- `Mobile/build/screenshots/ipad-library.png`
- `Mobile/build/screenshots/ipad-reader-agent.png`
