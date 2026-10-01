# App Distribution

## Status

Pending (default applied).

## Question

Should `stria-app` ship as a signed `.app` bundle (for example through the
existing Homebrew Cask scripts), or only as a SwiftPM executable?

## Default Applied

v0.1 ships `stria-app` as a SwiftPM executable (`swift run stria-app`). The
existing formula and cask scripts are renamed to `stria` and keep packaging
only the CLI binary `stria`. Bundling the `.app` (Info.plist, icon, signing)
is deferred until the user decides.

## Consequence

A GUI app started outside a shell does not inherit shell environment
variables, so API-key env vars may be missing. In that case the app shows the
name of the missing variable. Running from a terminal (`swift run stria-app`)
inherits the variables.
