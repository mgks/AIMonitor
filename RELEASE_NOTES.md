# AIMonitor v0.1.0

**Initial release**

A tiny native macOS menu bar app that shows the remaining usage, limits, and health of every AI service you use. No chat, no prompting, no playground. Just a glance at how much you have left.

## Features

- **Menu bar glance**: gauge icon plus optional usage percentage for one selected provider
- **Dual-window cards**: each provider shows both 5-hour and weekly quota with progress bars
- **Auto-refresh**: every 60 seconds (configurable), fetches on launch
- **7 providers** out of the box
- **Region switching**: MiniMax and Z.ai support international and China endpoints
- **Zero keychain prompts**: credentials stored in a local file, not the macOS Keychain
- **Open source**: MIT, no analytics, no backend

## Supported providers

| Provider | Type | What you see |
|---|---|---|
| **Claude Code** | OAuth (CLI) | 5h + 7-day windows, plan tier |
| **Codex (OpenAI)** | OAuth (CLI) | 5h + 7-day windows |
| **Kimi** | API key | 5h + Weekly coding plan quota |
| **MiniMax** | API key | 5h + Weekly Coding Plan quota |
| **Z.ai (GLM)** | API key | 5h + Weekly Coding Plan quota |
| **DeepSeek** | API key | Account balance (USD/CNY) |
| **OpenRouter** | API key | Credit balance + usage |

## Installation

Download `AIMonitor-0.1.0.dmg`, open it, drag AIMonitor to Applications. On first launch, right-click the app and select **Open** (required for unsigned apps).

## Known limitations

- **Notifications**: alerts require code signing to register with macOS. Will be fixed in a future signed release.
- **First launch**: macOS may show a security warning for unsigned apps. Right-click → Open to bypass.

## Requirements

- macOS 13 Ventura or later

---

**Download**: `AIMonitor-0.1.0.dmg` (396 KB)
