# Agent pane redesign (iPhone/iPad)

## Request

Simplify the agent pane: no "New Chat" / "Agent" / "page n of m" / "Done"
text, Chat / History / Summary as compact icons at the top left, scope
(Page / Nearby / PDF) as small icons, and a larger question input. Then feed
every current screen capture to Runway and adopt a more stylish, intuitive,
clutter-free proposal.

## References

- `references/agent-pane-redesign/mockup.png`: first macOS mockup (runwayml-cli).
- `references/agent-pane-redesign/proposal-iphone.png`, `proposal-ipad.png`:
  Runway `nano-banana-pro` proposals generated from all seven simulator
  screenshots (iPhone library, reader, agent, settings, OCR vendors; iPad
  library, reader with agent).

## Adopted design (Mobile/StriaMobile)

- Toolbar: Chat / History / Summary as an ink-blue icon capsule with a coral
  selected segment at the top left; resume, compose and close as round soft
  icon buttons at the right. No text labels.
- The lower-half pane on iPhone is a rounded sheet over the PDF with a shadow;
  the "Agent · Page n of m · Done" header is gone. The page counter is a
  floating ink pill over the PDF.
- A new chat has no title row. Existing chats show a one-line secondary title.
- Messages: user questions are ink bubbles on the right, answers soft rounded
  cards on the left, citations as small capsules.
- Composer: one large rounded card. The editor's placeholder follows the scope
  ("Ask about this page / these pages / this PDF"). The bottom row holds the
  model chip (a coral dot replaces the orange warning block; Settings is inside
  its menu), scope icons in a light capsule, the microphone and a round send
  button.
- iPad inline agent column: 50% of the width, 480 to 760 points.

Palette lives in `Flat` (`ink`, `coral`, `cardRadius`, `bubbleRadius`) with a
lighter ink for dark mode.
