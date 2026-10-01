# Architecture

## Status

Draft

## Overview

`KaibaViewer` is a Swift Package Manager project with a
library target, an executable target, tests, and release automation for Homebrew.

## Targets

- `KaibaViewerCore`: domain and command logic
- `KaibaViewerCLI`: command line entry point
- `KaibaViewerCoreTests`: package tests

## Release Surfaces

- Homebrew formula archives under `dist/homebrew/`
- Signed and notarized Cask DMGs under `dist/homebrew-cask/`
