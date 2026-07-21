# AIMonitor

A tiny native macOS menu bar app that shows the remaining usage, limits and health of every AI service you use. Think of it as Activity Monitor for AI quotas. No chat, no prompting, no playground. Just a glance at how much you have left.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![MIT](https://img.shields.io/badge/License-MIT-green)

## What it does

Click the menu bar icon and every enabled provider shows a card: remaining percentage, a progress bar, reset countdown, and last-updated time. The menu bar icon itself is the AIMonitor logo plus an optional usage summary percentage.

## Build

Requires only the macOS Command Line Tools (no Xcode needed):

```bash
make deploy    # build, bundle, deploy to /Applications, launch
```

For development:

```bash
make build     # swift build (release)
make run       # swift run (shows a dock icon, unlike the bundle)
make icon      # render AppIcon.icns only
make bundle    # assemble AIMonitor.app without deploying
make clean     # remove build artefacts and the .app
```

## Getting started

1. Launch AIMonitor. The menu bar icon appears top-right.
2. Click it, then **Preferences**.
3. **Providers** tab: toggle on the providers you use.
4. **Credentials** tab: paste each API key. Keys are stored in the macOS Keychain, never synced.
5. **General** tab: configure refresh interval, appearance, menu bar summary, notifications.

Only providers that are both enabled and have credentials appear in the popover.

## Supported providers

| Provider | Endpoints | Data source |
|---|---|---|
| **MiniMax** | `api.minimax.io` (international), `api.minimaxi.com` (China) | Coding Plan Remains API |
| **Z.ai (GLM)** | `api.z.ai` (international), `open.bigmodel.cn` (China) | Quota Limit monitor API |

More providers are added incrementally. Each is self-contained under `Sources/AIMonitor/Providers/<name>/`.

## Architecture

```
Sources/AIMonitor/
├── App/            SwiftUI shell: MenuBarExtra, cards, settings
├── Core/           Provider protocol, models, HTTP client, Keychain, scheduler
├── Providers/      One folder per provider, no cross-dependencies
└── Settings/       Preferences window
```

Every provider implements the `AIProvider` protocol: it owns how to fetch and parse its own quota data and returns a normalised `ProviderStatus`. No provider knows about another. Adding a provider is one new file plus one line in `ProviderRegistry`.

## License

MIT. See `LICENSE`.
