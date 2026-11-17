# Changelog

[Español](CHANGELOG.es.md)

## Unreleased

First local version of **ActionsWatcher**, version `1.0.0` (build `2`).

- Native menu bar app for macOS 14 and later, built with SwiftUI and AppKit.
- Connect with GitHub CLI or a personal access token stored in Keychain.
- Monitor active and recent workflow runs across up to 10 selected repositories.
- Search and filter runs, and open them from an interactive activity chart.
- Inspect jobs and steps with a progress ring, job map, step bars, and a step inspector.
- Respect macOS **Reduce Motion** and pause animations when the panel closes.
- Use a pointing-hand cursor for interactive controls and retain the text cursor in input fields.
- Navy and cream palette with distinct status colors.
- Failure and success notifications, configurable polling intervals, and launch at login.
- Conditional requests, pagination, tracking for long-running workflows, and backoff for errors and GitHub rate limits.
- Demo mode, build and packaging scripts, native preview rendering, and 24 core tests.
- Renamed Actions Bar to ActionsWatcher, retaining the existing preferences and Keychain identifiers.
