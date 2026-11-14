# App Distribution

## Status

Answered (2026-10-03): ship a signed `.app` through the Homebrew Cask, as
chilla does.

## Question

Should `stria-app` ship as a signed `.app` bundle (for example through the
existing Homebrew Cask scripts), or only as a SwiftPM executable?

## Decision

The Homebrew Cask `stria` installs a signed, notarized and stapled
`Stria.app` from a DMG and links the `stria` CLI that ships inside the app
(`Stria.app/Contents/MacOS/stria`), following chilla's cask. The CLI-only
formula is not published, because both would install `stria`.

## Consequence

An app started from Finder or the Dock does not inherit shell environment
variables. Stria imports the login shell's environment once at startup
(`LoginEnvironment.importIfNeeded`), so PATH (for `claude`, `codex`) and
API key variables are available; variables already set are kept.
