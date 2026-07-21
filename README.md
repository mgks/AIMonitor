# AIStat

A tiny native macOS menu bar app that shows the remaining usage, limits and health of every AI service you use. Think of it as Activity Monitor for AI quotas. No chat, no prompting, no playground. Just a glance at how much you have left.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![MIT](https://img.shields.io/badge/License-MIT-green)

## What it does

Click the menu bar icon and every configured provider shows a card: remaining percentage, a progress bar, reset countdown, and last-updated time. The menu bar icon itself is a coloured dot (green / yellow / red) plus the worst-case percentage across all providers.

## Build

Requires only the macOS Command Line Tools (no Xcode needed):

```bash
make bundle    # compiles, renders the app icon, assembles AIStat.app
open AIStat.app
```

For development:

```bash
make build     # swift build (release)
make run       # swift run (shows a dock icon, unlike the bundle)
make icon      # render AppIcon.icns only
make clean     # remove build artefacts and the .app
```

## Configure providers

Open **Preferences** from the menu bar (or `⌘,`):

1. **Credentials** tab: paste your API key for each provider. Keys are stored in the macOS Keychain, never synced, sent only to the provider you choose.
2. Pick the **region** for providers that have separate international and China endpoints.

## Supported providers

| Provider | Endpoints | Data source |
|---|---|---|
| **MiniMax** | `api.minimax.io` (international), `api.minimaxi.com` (China) | Coding Plan Remains API |
| **Z.ai (GLM)** | `api.z.ai` (international), `open.bigmodel.cn` (China) | Quota Limit monitor API |

More providers are added incrementally. Each is self-contained under `Sources/AIStat/Providers/<name>/`.

## Architecture

```
Sources/AIStat/
├── App/            SwiftUI shell: MenuBarExtra, cards, settings
├── Core/           Provider protocol, models, HTTP client, Keychain, scheduler
├── Providers/      One folder per provider, no cross-dependencies
└── Settings/       Preferences window
```

Every provider implements the `AIProvider` protocol: it owns how to fetch and parse its own quota data and returns a normalised `ProviderStatus`. No provider knows about another. Adding a provider is one new file plus one line in `ProviderRegistry`.

The three-tier data abstraction:

1. **Official API** (preferred) - e.g. MiniMax Coding Plan Remains, Z.ai Quota Limit.
2. **Response headers** - infer remaining quota from rate-limit headers.
3. **Authenticated scraping** (optional, future) - only when no API exists.

## License

MIT. See `LICENSE`.

