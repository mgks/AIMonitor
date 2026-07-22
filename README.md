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

### OAuth providers (auto-login via CLI tools)

These providers authenticate via their official CLI tools. Run the login command once, then enable the provider in Preferences. No manual API key entry needed.

| Provider | CLI login command | Credential location | Data source |
|---|---|---|---|
| **Claude Code** | `claude` | `~/.claude/.credentials.json` or macOS Keychain `Claude Code-credentials` | `api.anthropic.com/api/oauth/usage` |
| **Codex (OpenAI)** | `codex login` | `~/.codex/auth.json` | `chatgpt.com/backend-api/wham/usage` |

Tokens auto-refresh when expired. The credentials are read-only; AIMonitor never modifies them.

### API-key providers (enter key in Preferences)

| Provider | Endpoints | Region options | Data source |
|---|---|---|---|
| **Kimi** | `api.kimi.com` | International only | Coding plan usage (`/coding/v1/usages`) |
| **MiniMax** | `api.minimax.io`, `api.minimaxi.com` | International or China | Coding Plan Remains API |
| **Z.ai (GLM)** | `api.z.ai`, `open.bigmodel.cn` | International or China | Quota Limit monitor API |
| **DeepSeek** | `api.deepseek.com` | International only | Account balance |
| **OpenRouter** | `openrouter.ai` | International only | Credit balance + usage |

API keys are stored in the macOS Keychain (service `dev.mgks.aimonitor`), never written to disk or synced.

## Prerequisites for OAuth providers

To use Claude Code and Codex providers, you need their CLI tools installed and authenticated:

```bash
# Claude Code (Anthropic)
npm install -g @anthropic-ai/claude-code
claude              # follow the login flow

# Codex (OpenAI)
npm install -g @openai/codex
codex login         # follow the login flow
```

After login, the credentials are written to disk. AIMonitor reads them automatically.

## Architecture

```
Sources/AIMonitor/
├── App/            SwiftUI shell: MenuBarExtra, cards, settings
├── Core/           Provider protocol, models, HTTP client, Keychain, scheduler,
│                   OAuth credentials reader
├── Providers/      One folder per provider, no cross-dependencies:
│   ├── Claude/     OAuth, auto-refresh, usage endpoint
│   ├── Codex/      OAuth, auto-refresh, usage endpoint
│   ├── Kimi/       API key, coding plan
│   ├── MiniMax/    API key, coding plan remains
│   ├── Zai/        API key, quota limit (no Bearer prefix)
│   ├── DeepSeek/   API key, account balance
│   └── OpenRouter/ API key, credit balance
└── Settings/       Preferences window
```

Every provider implements the `AIProvider` protocol: it owns how to fetch and parse its own quota data and returns a normalised `ProviderStatus`. No provider knows about another. Adding a provider is one new file plus one line in `ProviderRegistry`.

The three-tier data abstraction:

1. **Official API** (preferred) - e.g. MiniMax Coding Plan, Z.ai Quota Limit.
2. **OAuth usage endpoint** - Claude Code, Codex read quota via undocumented usage endpoints.
3. **Account balance** - DeepSeek, OpenRouter show credit balance when no quota window exists.

## Adding a new provider

1. Create `Sources/AIMonitor/Providers/YourProvider/YourProvider.swift`.
2. Implement `AIProvider` (fetch + parse + return `ProviderStatus`).
3. Add it to `ProviderRegistry.makeDefault()`.
4. Add credential fields in `SettingsView.swift`.

For OAuth providers, define a `CredentialSchema` and use `OAuthReader.load()`.