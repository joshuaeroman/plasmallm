# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**PlasmaLLM** is a KDE Plasma 6 widget providing a chat interface to OpenAI-compatible LLM endpoints with system info gathering, markdown rendering, and shell command execution.

- **Language**: QML (Qt 6) + JavaScript — no external dependencies
- **Framework**: KDE Plasma 6.0+ (X-Plasma-API-Minimum-Version: 6.0)
- **License**: GPL-2.0-or-later

## Development Workflow

```bash
make install-dev          # Symlink install (changes apply on Plasma restart)
plasmashell --replace &     # Restart Plasma to reload
journalctl -u plasmashell --follow  # View logs
make remove               # Uninstall
```

There is no build step, test suite, or linter. QML is interpreted at runtime. After editing files, restart Plasma to test.

**Logging**: Use `console.warn()` in QML/JS — `console.log()` is filtered by default. Output appears in the terminal where `plasmashell --replace` was launched.

## Architecture

### File Responsibilities

| File | Role |
|------|------|
| `main.qml` | Root PlasmoidItem. Chat state (`chatMessages` for API, `displayMessages` for UI), system info gathering, message routing, command execution via P5Support.DataSource, chat persistence |
| `FullRepresentation.qml` | Chat UI: scrollable message list, input field, header with provider/model info, toolbar |
| `ChatMessage.qml` | Message bubble. Strips code blocks from assistant markdown (via `Api.stripCodeBlocks()`) and renders them as separate CommandBlock widgets |
| `CommandBlock.qml` | Interactive code block with Save/Copy/Run/Terminal buttons |
| `api.js` | `buildSystemPrompt()`, `sendChatRequest()`, `fetchModels()`, `stripCodeBlocks()`, `parseCommandBlocks()` |
| `configGeneral.qml` | Settings UI with 20+ provider presets, model fetching, auto-run/auto-share toggles |
| `config/main.xml` | Configuration schema for `Plasmoid.configuration` |

### Data Flow

1. **Startup**: `regatherSysInfo()` fires up to 12 config-gated shell commands in parallel. 3s timeout fallback if any hang (`sysInfoTimeout` Timer).
2. **System prompt**: Built from gathered `sysInfo` + custom prompt + auto-run warnings when all info collected.
3. **User message** → `sendMessage()` → appends to both ListModels → `sendToLLM()` (caps messages to system prompt + last `maxApiMessages`).
4. **LLM response** → `parseCommandBlocks()` extracts bash/sh/shell/zsh fenced blocks → updates placeholder → auto-runs if enabled.
5. **Command execution** → P5Support.DataSource `onNewData` → `handleCommandOutput()` (truncates at 50KB) → auto-shares if enabled.
6. **Agentic loop**: auto-run + auto-share enabled → steps 4→5→4 repeat automatically.

### Key Design Decisions

- **Dual ListModels**: `chatMessages` = API history (sent to LLM); `displayMessages` = UI state (includes command output, errors, extracted commands). Never conflate them.
- **Code block stripping**: Assistant messages have code blocks removed via `stripCodeBlocks()` and rendered as CommandBlock widgets. The system prompt tells the LLM about this so it doesn't write "run this command:" transitions.
- **Command storage**: Commands stored as `\x1F`-delimited strings in `commandsStr` because QML ListModel doesn't support nested arrays.
- **Streaming**: SSE streaming is enabled (`stream: true`) for all requests including those with tools. Since QML XHR lacks proper `onprogress` events, a 50ms poll timer reads the growing `responseText` buffer and parses new SSE chunks. Tool call deltas are accumulated across chunks and passed to `onComplete`.
- **Signal decoupling**: ChatMessage and CommandBlock communicate upward via signals, not direct `root.` references.

### Message Roles

`system` (hidden) | `user` (right-aligned) | `assistant` (left, markdown) | `command_running` (spinner) | `command_output` (monospace) | `error` (negative theme color)

## Common Modifications

**Adding a system info field**: Add command to `systemCommands` array → add case in `handleSystemInfo()` → update `buildSystemPrompt()` in api.js.

**Adding a config option**: Add entry to `main.xml` → add `cfg_` property + control in `configGeneral.qml` → access via `Plasmoid.configuration.<name>`.

## Translations

All user-facing strings use KDE's `i18n()` function. Translation files live in `package/contents/locale/`.

```bash
make translations          # Extract strings, merge into .po files, validate, and compile
```

The make target will report any untranslated or fuzzy strings with their line numbers. All strings must be translated before the target will compile `.mo` files.

**Adding a new translatable string**: Wrap the string with `i18n("...")` in QML/JS, then run `make translations` — it extracts strings automatically. Fill in translations for all 11 languages (de, es, fr, fr_CA, it, ja, nb, nl, pt_BR, tr, zh_CN) in the corresponding `.po` files.

**Installing packages for translation work**: Use `distrobox enter my-distrobox` — pip and Python packages (e.g. `polib`) must be installed inside the distrobox, not on the host.

## Code Style

- SPDX headers on all files: `SPDX-FileCopyrightText: 2026 Joshua Roman`
- Import order: Qt → KDE Plasma → P5Support → Kirigami → local JS
- Use `var` for declarations, `function` keyword (not arrows) — QML JS standard
- Use theme colors from `Kirigami.Theme`, not hardcoded values

## Environment

- When intending to run multiple commands, create a script file and execute that instead of one at a time
- After making changes, run `make install` and restart Plasma

## Git Workflow

- **Never push directly to `master`**. Always create a feature branch and open a PR.
- **Never commit or push unless explicitly asked.** Make changes, then wait for the user to review and say when to commit and when to push.
- Branch naming: `feature/<short-description>` or `fix/<short-description>`
