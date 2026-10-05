# Voice Input for the Agent Chat

## Status

Implemented.

Implementation notes and deviations:

- Modern Apple analysis is split into `AnalyzerSpeechEngine.swift`; the public
  `AppleSpeechEngine` chooses it on macOS 26 / iOS 26 and the legacy recognizer
  on older systems. Language assets are reserved and installed on demand.
- The vendor model control combines catalog suggestions with a directly editable
  custom ID field; an empty field keeps the catalog's first default.
- Dictation appends to the composer. Edits outside the dictated range are kept;
  if the user edits inside that range, subsequent dictation starts a new range
  at the end rather than overwriting the user's edit.
- `Esc` also cancels permission requests, preparation and transcription. `m`
  stops a recording even after the shortcut focuses the composer.
- Verification uses an offline copy of resolved dependencies and a separate Mac
  scratch directory to preserve `.build/`. In the restricted environment the
  Mac build/test commands need `-Xswiftc -gnone` because dSYM generation is
  denied. The full test suite is run with `--no-parallel`: the concurrent run
  stalled in this sandbox without reporting a test failure. Real microphone
  use, asset installation and vendor requests are left
  to device testing; automated tests use fake engines and gateway clients.

## Goal

The user can speak a question instead of typing it. Speech becomes text in
the chat composer (live, while speaking, with the on-device engine), the user
can edit it, and it is sent as a normal user message, or sent automatically
when Settings asks for it. Apple's on-device recognition is the default;
API vendors (OpenAI, Gemini, OpenRouter) can be chosen instead.

## Engines

| Engine | How | Notes |
| --- | --- | --- |
| `apple` (default) | Speech framework on device | No audio leaves the device. Live partial text. macOS 26 / iOS 26: `SpeechAnalyzer` + `SpeechTranscriber` (assets installed on demand through `AssetInventory`); earlier systems: `SFSpeechRecognizer` with `requiresOnDeviceRecognition` when supported, else server-based Apple recognition (stated in Settings). |
| `openai`, `gemini`, `openrouter` | Record to an `.m4a` (AAC) file, then transcribe through agent-gateway's `GatewayTranscribing` (`transcribe(GatewayTranscriptionParams)`) | Text appears after the user stops. The API key comes from the same credential table as chat (`agent.credentials.<vendor>`, environment on macOS, Keychain on iOS). Audio is sent to the vendor (stated in Settings). |

Anthropic, Cursor and the CLI vendors do not offer audio input and are not
listed. On iOS the CLI vendors are never offered anyway.

## Config (`voice`, per device)

| Key | Default | Meaning |
| --- | --- | --- |
| `voice.engine` | `"apple"` | `apple`, `openai`, `gemini` or `openrouter` |
| `voice.model` | `null` | transcription model for a vendor engine (null = the vendor's first default, `GatewayTranscriptionModels.defaults`) |
| `voice.language` | `"auto"` | `auto` (the system's preferred language) or a BCP-47 tag such as `ja-JP`, `en-US` |
| `voice.autoSend` | `false` | send the message as soon as the transcript is final |
| `voice.maxSeconds` | `300` | recording limit (10...1800); recording stops at the limit |

Validation follows the other sections; `stria config get/set` exposes the
keys. For vendor engines the language passed to the vendor is the ISO-639-1
part (`ja`), or omitted for `auto`.

## Behaviour

`SpeechInputController` (StriaCore, `@MainActor @Observable`, platform
neutral API, engines behind a `SpeechTranscriptionEngine` protocol so tests
use a fake):

- States: `idle`, `requestingPermission`, `preparing` (asset download for
  the on-device model), `recording(level)`, `transcribing` (vendor upload),
  `failed(message)`.
- `toggle()` starts or stops; `cancel()` discards. Starting asks for
  microphone (and, for `apple`, speech recognition) permission the first
  time; a denial shows how to enable it in System Settings.
- While recording with `apple`, partial text replaces the dictated range in
  the composer (text typed before the dictation is kept). With a vendor, a
  "Transcribing..." indicator shows after stop and the final text is
  inserted at the end of the composer.
- On the final transcript: if `voice.autoSend` and the text is not empty, the
  composer sends it (`AgentPaneViewModel.submit()`); otherwise the text stays
  for editing with focus in the input.
- Silence of 2 seconds after speech does not stop automatically in the first
  version; `voice.maxSeconds` does.
- Errors (no permission, no microphone, unsupported language, vendor errors)
  appear in the agent pane notice line and never lose typed text.
- Temporary audio files live in the cache directory and are deleted after
  transcription or cancel.

## UI

- Composer (Mac and iOS): a microphone button next to Send. Idle: `mic`.
  Recording: `mic.fill` in red with a small level indicator and elapsed time;
  Transcribing: a spinner. Tooltip names the shortcut and the engine.
- Mac shortcuts: single key `m` in the reader (shows the agent pane, focuses
  the input and starts dictation; `m` again stops), and Agent > Start/Stop
  Dictation `Cmd-Shift-M` in the menu (`Cmd-Option-M` is the system's "Minimize
  All"). Esc while recording cancels.
- Settings > Voice Input (Mac and iOS): engine picker (Apple on-device first;
  vendors with a "(sends audio to <vendor>)" note), model (vendor engines,
  catalog plus custom), language picker (Auto + common languages), "Send
  automatically after dictation", recording limit, and a line about where
  audio goes.

## Permissions and packaging

- Info.plist: `NSMicrophoneUsageDescription` ("Stria records your voice to
  turn it into a chat message.") and `NSSpeechRecognitionUsageDescription`
  ("Stria turns your speech into text for the agent chat.") in
  `Resources/StriaInfo.plist` (embedded in the SwiftPM app), in the release
  script's generated Info.plist, and in `Mobile/project.yml`.
- The release app is signed with the hardened runtime, which needs the
  `com.apple.security.device.audio-input` entitlement for the microphone:
  `Resources/Stria.entitlements`, passed to `codesign --entitlements` for the
  app bundle in `scripts/build-homebrew-cask-release.sh`.

## Tests

Controller state machine with a fake engine (start/stop/cancel, partial
updates keep pre-typed text, final text inserted, autoSend submits, errors
keep the text, max duration), vendor engine request mapping (model default,
language ISO-639-1, credential lookup through the platform credential
environment, unsupported vendors), config keys and validation.
