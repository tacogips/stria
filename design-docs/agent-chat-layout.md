# Agent chat layout

## Request

Increase the chat pane width and editor height, show a warning when agent
configuration is missing, remove the introductory PDF question text, and keep
the empty transcript small when starting a new conversation.

## Implementation

- macOS uses a 520-point default pane, a 480-point minimum, and an 800-point
  maximum. Existing narrower preferences are clamped to the new minimum.
- iPad retains the desktop-style sidebar and uses 42% of the available width,
  bounded between 420 and 520 points. Compact readers on iPhone, iPad, and
  macOS show the agent below the PDF, using half the available reader height.
  The header shows the live current page and a Done button. The PDF remains
  visible and interactive, including while navigating citation links.
- Compact mobile composers use a smaller editor and scroll when space is
  limited, including with the software keyboard open.
- A new chat reserves 32 points for its empty transcript. The editor fills the
  remaining space. Existing conversations restore transcript space and limit
  editor height to preserve readable conversation history.
- Configuration warnings distinguish missing vendor/model selection, missing
  API credentials, and unavailable platform capabilities. Settings opens from
  the warning. macOS CLI vendors do not require an API key.
- Credential save, deletion, synchronization changes, and application activation
  refresh observable credential availability without replacing the editor.
- The introductory PDF question paragraph is removed. The macOS placeholder
  and editor accessibility labels use “Question”.

## Verification

The earlier editor changes were visually checked with an isolated macOS chat
preview, iPad sidebar, and iPhone chat sheet.
The empty transcript remained small and setup warnings were visible. On iPhone,
the editor and send controls remained visible with the software keyboard open.
No real provider requests or API credentials were used in this verification.

The lower-half pane update passes `swiftlint` (zero violations),
`swift build --target StriaApp`, and an unsigned generic iOS Simulator
`xcodebuild build`. Interactive visual verification of the new split layout
is still pending.

Configuration tests cover macOS and iOS, missing credentials, adding/removing
an in-memory key, absent vendor/model selection, and macOS CLI selection.
Conversation tests cover the new-chat state before sending, after sending,
and after resetting the conversation while preserving saved threads.
