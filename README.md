# ActionsWatcher

[Español](README.es.md)

ActionsWatcher is a native macOS menu bar app for monitoring GitHub Actions. It uses SwiftUI and AppKit and connects directly to GitHub without third-party packages or intermediary services.

See workflow runs, inspect jobs and steps, and get completion notifications from the menu bar.

## Build and launch

The app runs on **macOS 14 or later**. To build it, you need **Swift 6** and the **macOS 15 SDK or later**, available with Xcode 16, its Command Line Tools, or a newer version compatible with your Mac. [Xcode system requirements](https://developer.apple.com/xcode/system-requirements/)

From the repository root, build and launch the app.

```sh
./scripts/run.sh
```

To explore sample data without connecting to GitHub, quit any running instance of ActionsWatcher and launch demo mode.

```sh
./scripts/run.sh --demo
```

The script creates `build/ActionsWatcher.app`, which you can reopen by double-clicking it. The app appears in the menu bar. The script builds for your Mac's architecture and signs the bundle ad hoc for local use.

## Connect to GitHub

The app interface is in Spanish. This guide uses the labels shown in the app so you can find each control.

Click **Usar mi sesión de GitHub CLI** to use an existing GitHub CLI session. ActionsWatcher looks for `gh` in standard Homebrew locations and keeps the token in memory during the session. To sign in to GitHub CLI, run `gh auth login --hostname github.com`. You can also connect with a personal access token.

1. Click **Conectar con un token personal**, then **Crear token** to create a fine-grained personal access token.
2. Select a resource owner and the repositories you want to monitor.
3. Set **Actions** to **Read-only**. GitHub already includes read access to **Metadata**.
4. Paste the token into the app, click **Conectar**, and select the repositories to monitor.

A fine-grained token has one resource owner. For private organization repositories, GitHub may require SSO during token creation and the organization may require approval. ActionsWatcher connects to `github.com`. [GitHub personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) · [SSO authorization](https://docs.github.com/en/enterprise-cloud@latest/authentication/authenticating-with-single-sign-on/authorizing-a-personal-access-token-for-use-with-single-sign-on)

## Monitor workflow runs

1. Click **Repositorios** (Repositories) at the bottom of the panel and select up to 10 repositories. You can search the list or add a repository by its `owner/repo` name or GitHub URL.
2. Browse active and recent runs using the filters, search field, or activity chart. Clicking a cell in the chart opens its run.
3. Open a run to see its progress ring and job map. Each card shows the job status and completed step count. Click **Ver los N jobs** to show the remaining jobs.
4. Select a job card and click a point on the timeline to inspect a step. **Seguir actual** resumes following the current step. **Ver los N pasos** expands the full step list.
5. Open **Preferencias** (Settings) to change the polling interval, notifications, or launch at login. The refresh button in the header requests a refresh when GitHub's retry window allows it.

The ring shows completed jobs out of the jobs GitHub has reported, including failed, canceled, and skipped jobs. The bars show step progress within each job. Use GitHub for the full logs and job dependencies.

## Features

- Menu bar status icon with an active run count. Right-click it to open the panel or quit.
- Searchable, paginated repository list with support for up to 10 selected repositories.
- Active and recent runs with workflow, branch, commit, duration, and attempt. The app also queries active runs separately to keep tracking older runs that are still in progress.
- All, active, and failed run filters. Search by repository, branch, workflow, or title.
- Job and step inspection for the displayed attempt, with failed jobs listed first and abbreviated action commit hashes. Hover over a truncated label to see the full name.
- Live job updates while viewing a run and pagination for large job matrices.
- Activity animations that respect macOS **Reduce Motion** and pause when the panel closes.
- Failure notifications and optional success notifications. In **Preferencias**, click **Activar notificaciones en macOS** and grant permission. Notifications cover runs the app observed in progress during the current session. Click a notification to open the run in GitHub.
- Polling every 15, 30, 60, or 120 seconds, with conditional ETag requests and limited concurrency. The app respects GitHub's retry window, backs off when all repository requests fail, and marks affected data as stale.
- Optional launch at login. Move the app to Applications before enabling this setting. macOS may prompt you to approve the login item.
- Demo mode with labeled sample data and offline browsing.

The menu bar indicator prioritizes active runs. When they finish, it summarizes the latest known result per repository, workflow, and branch. A new successful run clears an earlier failure from that combination's summary.

ActionsWatcher monitors GitHub Actions runs. For a deployment that continues after its workflow finishes, check the deployment provider for its status.

## Data and credentials

ActionsWatcher makes read-only requests directly to the GitHub API and has no analytics. It saves manually entered tokens in macOS Keychain and keeps tokens obtained from GitHub CLI in memory. Local preferences store the selected repositories, connection mode, polling interval, and notification options.

Click **Desconectar** (Disconnect) to remove the token stored by ActionsWatcher and clear the repository selection. You can continue using your GitHub CLI session.

## Appearance

| Use | Color |
| --- | --- |
| Background | `#010736` |
| Cards | `#0D1C42` |
| Raised surfaces and selection | `#22396F` |
| Primary text and accents | `#FCF1D0` |

Status icons and labels accompany the colors for success, waiting, and failure. Controls have accessibility labels. Interactive controls use a pointing-hand cursor, and text fields retain the text cursor.

## Development and validation

```sh
./scripts/swift-local.sh test
./scripts/build-app.sh
codesign --verify --strict 'build/ActionsWatcher.app'
```

The core tests use mocked HTTP responses. See the development guide for the architecture, demo screenshots, and local validation steps. [Development guide](docs/DEVELOPMENT.md) · [Changelog](CHANGELOG.md)

## Repository layout

| Path | Contents |
| --- | --- |
| `Sources/ActionsWatcherCore` | Models, HTTP client, and monitoring rules |
| `Sources/ActionsWatcher` | Interface, menu bar, preferences, Keychain, and notifications |
| `Tests/ActionsWatcherCoreTests` | HTTP client and monitoring tests |
| `scripts` | Build and packaging scripts and icon generation |
| `Resources` | macOS bundle metadata |
| `docs` | Development and validation notes |

## License

ActionsWatcher is available under the MIT License. [License text](LICENSE)
