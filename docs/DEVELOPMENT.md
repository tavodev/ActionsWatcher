# ActionsWatcher development guide

[Español](DEVELOPMENT.es.md)

Swift Package Manager organizes the project into three targets, `ActionsWatcher`, `ActionsWatcherCore`, and `ActionsWatcherCoreTests`. The app uses frameworks from the macOS SDK.

## Build and run

Install the tools listed in the README, then run these commands from the repository root. [Build requirements](../README.md#build-and-launch)

```sh
./scripts/build-app.sh
open build/ActionsWatcher.app
```

`build-app.sh` builds in release mode, assembles the app bundle, generates the icon from code, and signs the bundle. For a debug bundle, run `CONFIGURATION=debug ./scripts/build-app.sh`. Open `Package.swift` to work in Xcode and use the script to produce the `.app` bundle.

`scripts/swift-local.sh` keeps SwiftPM caches and configuration in `.build/`. It disables SwiftPM's build sandbox so the compiler can run in environments that already impose a sandbox. This setting applies to the build process.

Git excludes `.build/`, `.swiftpm/`, `build/`, and `artifacts/`. The script builds for the host Mac's architecture and signs ad hoc by default. Use `SIGN_IDENTITY` to select another signing identity. To distribute a binary signed with Developer ID, enable Hardened Runtime, include a secure timestamp, and notarize the app. [Apple's macOS notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

Include the copyright notice and license text when distributing copies of the project. [MIT License](../LICENSE)

## Architecture

| Component | Responsibility |
| --- | --- |
| `ActionsWatcherApp.swift` | App lifecycle, `NSStatusItem`, popover, notifications, and native preview rendering |
| `MonitorStore.swift` | UI and session state, repositories, polling, and completion notifications |
| `Credentials.swift` | GitHub CLI token retrieval and personal access token storage in Keychain |
| `GitHubClient.swift` | GET requests to GitHub, in-memory ETag caching, pagination, and rate limits |
| `Models.swift` | Run states, repository validation, sorting, and tracking completion transitions |
| `WorkflowProgress.swift` | Progress counts, job priority, and commit hash abbreviation |
| `ProgressVisuals.swift` | Progress ring, job cards, step bars, and activity indicators |
| `RunDetailView.swift` | Job map and interactive step inspector |
| `HandCursor.swift` | Pointing-hand cursor for enabled controls, including macOS 14 support |
| `Theme.swift` | Palette, shared styles, and status presentation |

The HTTP client is a Swift actor, and UI state is isolated to the main actor. The app polls up to three repositories at a time. For each repository, it fetches the 20 most recent runs and paginates active runs separately. If a previously active run disappears from those lists, the app looks it up by ID to retrieve the result.

The app fetches paginated jobs for the run attempt when you open or refresh a run. The job map groups jobs by status, with failed, active, and waiting jobs prioritized in that order.

Activity animations use `TimelineView` and pause when the popover closes. The macOS **Reduce Motion** setting disables continuous motion and animated transitions. The cursor implementation uses `pointerStyle` on macOS 15 and later and AppKit cursor rectangles on macOS 14.

## Local data and bundle identity

**ActionsWatcher** is the product, executable, and package name. The app keeps the original `dev.tavodev.actions-bar` identifier in `Info.plist` and in its Keychain service so existing installs retain their preferences and stored credentials. Changes to these identifiers require a data migration.

Preferences store selected repositories, the connection mode, the polling interval, and notification options. Personal access tokens are stored in Keychain. Tokens retrieved from GitHub CLI and cached API responses are held in memory. Disconnecting from ActionsWatcher leaves the GitHub CLI session active.

## Validation

```sh
./scripts/swift-local.sh test
./scripts/build-app.sh
codesign --verify --strict build/ActionsWatcher.app
plutil -lint build/ActionsWatcher.app/Contents/Info.plist
git diff --check
```

The tests use mocked HTTP responses and cover progress, states, sorting, completion tracking, workflow retries, pagination, and rate limits. The manual checks below cover the interface and connection to a real account.

With the bundle built and an active macOS desktop session, generate screenshots using sample data.

```sh
build/ActionsWatcher.app/Contents/MacOS/ActionsWatcher --preview artifacts/previews
```

Check `dashboard.png`, `detail.png`, `job-inspector.png`, `detail-failure.png`, `detail-waiting.png`, `repositories.png`, `settings.png`, and `onboarding.png`. AppKit renders the native controls and needs access to macOS graphics services even when the build itself succeeds in a sandbox.

The command also captures three pairs of activity indicator frames. Compare them with Python 3.

```sh
python3 - <<'PY'
from pathlib import Path

for name, expected_equal in [
    ("motion", False),
    ("reduced-motion", True),
    ("paused-motion", True),
]:
    first = Path(f"artifacts/previews/{name}-1.png").read_bytes()
    second = Path(f"artifacts/previews/{name}-2.png").read_bytes()
    assert (first == second) == expected_equal, name
    print(f"{name}: OK")
PY
```

For manual validation, connect to GitHub and select repositories. Open a run, switch between jobs and steps, check the cursor over interactive controls, and verify a completion notification. Repeat the animation and navigation checks with macOS **Reduce Motion** enabled.
