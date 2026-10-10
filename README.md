# PlasmaLLM

PlasmaLLM is a system-aware AI assistant widget for the KDE Plasma 6 desktop. It provides a native interface to various LLM endpoints, integrating system information gathering, web search, and shell command execution directly into your desktop workflow.

![License: GPL-2.0-or-later](https://img.shields.io/badge/License-GPL--2.0--or--later-blue.svg)
![KDE Plasma 6](https://img.shields.io/badge/Plasma-6.0%2B-blue)
![Qt 6](https://img.shields.io/badge/Qt-6.0%2B-green)

PlasmaLLM is designed for quick tasks and system-integrated workflows—not as a replacement for full-featured chat applications. It excels at answering technical questions about your system, running terminal commands, and providing an agentic interface for desktop automation.

## Features

- **Multi-Provider Support**: Connects to Ollama, LM Studio, OpenAI, Anthropic Claude, Google Gemini, OpenCode Zen/Go, and any OpenAI-compatible API.
- **System Awareness**: Optionally gathers hardware, OS, and environment info to provide context for assistant responses.
- **Tool-Calling System**: Modular architecture allowing LLMs to interact with the filesystem, run shell commands, and fetch web data (with user approval).
- **Interactive Terminal Blocks**: View, copy, or execute suggested terminal commands. Supports session multiplexing via `tmux` or `screen`.
- **Web Search Integration**: Native support for DuckDuckGo and SearXNG.
- **Vision Support**: Supports image attachments for providers with multimodal capabilities (e.g., Gemini).
- **Voice Input (STT)**: Hold-to-talk microphone that transcribes via an OpenAI-compatible `/audio/transcriptions` API (e.g. OpenRouter `openai/gpt-transcribe`) or a local OpenAI Whisper CLI, then sends the text to your active chat profile.
- **Secure Storage**: Integrates with KWallet for secure management of API keys and secrets.
- **Markdown Rendering**: Full support for markdown, including syntax highlighting for code blocks and LaTeX for mathematical notation.
- **Context Compaction**: Save tokens and speed up local model processing by reducing the size of the context that needs to process.

## Requirements

- KDE Plasma 6.0+
- Qt 6
- Optional: `python3-matplotlib`, `python3-dbus`, and `python3-gobject` (or distro equivalents) for Mathtext LaTeX rendering
- Optional: `qt6-qtmultimedia` (or distro equivalent) for microphone capture via Qt Multimedia (Voice Input)
- Optional: `pw-record`, `ffmpeg`, or `arecord` as a shell fallback if Qt capture is unavailable (Voice Input)
- Optional: OpenAI Whisper CLI (`whisper` from the `openai-whisper` Python package) for local speech-to-text
- Optional: `tmux` or `screen` for session multiplexing.

### Voice input setup

1. Open **Configure PlasmaLLM → Speech to Text**.
2. Enable **microphone input**.
3. Choose **STT backend**.

#### OpenAI-compatible API

4. Choose a provider (e.g. **OpenRouter**), confirm endpoint `https://openrouter.ai/api/v1`.
5. Click **Fetch models** (this queries transcription models — OpenRouter does **not** list them on the normal chat model list).
6. Select a model such as `openai/gpt-transcribe`, save your API key.

#### OpenAI Whisper (local CLI)

4. Select **OpenAI Whisper (local CLI)**.
5. Set **Command** if `whisper` is not on your PATH. The field is a prefix inserted as-is, for example `python3 -m whisper` or `toolbox run whisper`.
6. Choose a model (`base` is the default). The first run may download weights into `~/.cache/whisper`.
7. Optional: task (transcribe/translate), device (`cpu`/`cuda`), FP16, threads, initial prompt, extra CLI args.
8. Use **Test CLI** to confirm the command responds to `--help`. No STT API key is required.

Then, for either backend:

9. **Mic button** mode:
   - **Auto** (default): short click toggles recording; press and hold (~250 ms+) for push-to-talk until release.
   - **Hold to talk**: press-and-hold only.
   - **Toggle**: click to start, click again to stop and send.
10. Optional: set a **Voice shortcut** (default **Ctrl+M**) while the panel is open and focused. It follows the same **Mic button** mode (auto / hold / toggle). Clear the field to disable. To open the panel from elsewhere, use **Activate widget** on the dialog’s Shortcuts page.
11. Your **active chat profile** (General page) is still used for the conversation; STT is only the speech engine.

---

## Screenshots

<img width="711" height="703" alt="image" src="https://github.com/user-attachments/assets/fd9f1c74-778d-44ff-b7dd-4b3870b4baad" />

<img width="711" height="703" alt="image" src="https://github.com/user-attachments/assets/7a801fb0-720a-4c9d-a1dd-3995cdef5f71" />

<img width="771" height="947" alt="image" src="https://github.com/user-attachments/assets/8a6ddd79-2398-4f81-a803-56daa4e44fed" />

<img width="676" height="704" alt="image" src="https://github.com/user-attachments/assets/44814c7e-00e5-4946-8250-e0c5ab158b7e" />

<img width="909" height="787" alt="image" src="https://github.com/user-attachments/assets/e1f3855c-cc49-4f27-affa-6fc5780c718d" />

<img width="875" height="849" alt="image" src="https://github.com/user-attachments/assets/94007511-2bfd-4680-8bd0-8c1c4df1ba21" />

---

## Installation

### From the KDE Store
You can install PlasmaLLM directly from the Plasma widget explorer:
**Add Widgets** → **Get New Widgets** → **Download New Plasma Widgets** → Search for "PlasmaLLM".

### From GitHub Releases
Download the latest `.plasmoid` file from the [Releases](https://github.com/joshuaeroman/plasmallm/releases) page:

```bash
plasmapkg2 --install PlasmaLLM-*.plasmoid
```

### From Source
## Note: Building code directly from master branch may pull in unreleased features without translations from English. Translations are only done in release prep. Checkout a specific tag first if you'd prefer to build a particular release.
```bash
git clone https://github.com/joshuaeroman/plasmallm.git
cd plasmallm
make install
plasmashell --replace &
```

For development (symlinks the package directory):
```bash
make install-dev
```

### Standalone App
PlasmaLLM can also run as a normal application window instead of a panel widget. It still uses the KDE Plasma 6 libraries, and additionally needs the distro's PySide6 package (`python3-pyside6` on Fedora). A pip-installed PySide6 will not work, because it bundles its own Qt, which cannot load KDE's QML plugins.

From source:
```bash
make standalone            # build into build/standalone and create PlasmaLLM-standalone-<version>.tar.gz
make install-standalone    # install to ~/.local (override with PREFIX=...); adds an app menu entry
plasmallm                  # or launch "PlasmaLLM" from the app menu
```

`make standalone-no-i18n` skips the translation refresh, and `make run-standalone` builds and runs it from the build directory.

From a release tarball:
```bash
tar -xzf PlasmaLLM-standalone-<version>.tar.gz
cp -r plasmallm-<version>/. ~/.local/      # or run plasmallm-<version>/bin/plasmallm in place
```

On first launch, settings are imported from an existing PlasmaLLM widget (or later with `plasmallm --import-plasma-config`). After that, the app keeps its own settings in `~/.config/plasmallmrc`. Chat history and KDE Wallet keys are shared with the widget. `plasmallm --configure` opens the settings window on start.

To uninstall, run `make remove-standalone` (with the same `PREFIX` used to install). Settings in `~/.config/plasmallmrc` and window sizes in `~/.local/state/plasmallmstaterc` are kept.

#### Flatpak
The standalone app can also be built as a Flatpak bundle. The build needs `flatpak-builder` and Flathub added to your *per-user* Flatpak installation, because dependencies (the KDE 6.11 SDK and runtime and the PySide base app, a few GB) are installed per-user on the first build:

```bash
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
make flatpak               # creates PlasmaLLM-<version>.flatpak
make install-flatpak       # or: flatpak install --user PlasmaLLM-<version>.flatpak
```

To uninstall: `flatpak uninstall --user com.joshuaroman.plasmallm`.

The Flatpak is not meaningfully sandboxed. PlasmaLLM's commands (the run-command tool, system info, TTS/STT tools, saving chats) run on the host through `flatpak-spawn --host`. The app can access your home directory and `/tmp`, so it shares files with those commands and with the widget. It uses your normal `~/.config` and `~/.local/share`, not `~/.var/app`.

### Make Targets

| Target | Description |
|---|---|
| `make` / `make package` | Refresh translations, ask for a version number, and build `PlasmaLLM-<version>.plasmoid` |
| `make package-no-i18n` | Build the `.plasmoid` without refreshing translations |
| `make install` | Install the widget to `~/.local/share/plasma/plasmoids` |
| `make install-dev` | Install the widget as a symlink to `package/`, so source edits take effect after restarting Plasma |
| `make remove` | Uninstall the widget |
| `make standalone` | Refresh translations and build the standalone app into `build/standalone` and `PlasmaLLM-standalone-<version>.tar.gz` |
| `make standalone-no-i18n` | Build the standalone app without refreshing translations |
| `make run-standalone` | Build the standalone app (no translation refresh) and run it from `build/standalone` |
| `make install-standalone` | Install the built standalone app to `~/.local`, or to `PREFIX=...` |
| `make remove-standalone` | Uninstall the standalone app (use the same `PREFIX`) |
| `make flatpak` | Build the `PlasmaLLM-<version>.flatpak` bundle |
| `make install-flatpak` | Install the Flatpak bundle for the current user |
| `make release` | Refresh translations, then build the `.plasmoid`, the standalone tarball and the Flatpak, all with the version entered at the prompt |
| `make release-no-i18n` | Build all three release files without refreshing translations |
| `make translations` | Update the `.pot` and `.po` files from the source, fail if any string is untranslated or fuzzy, then compile the `.mo` files |
| `make check-translations` | Update the `.pot` and `.po` files and report untranslated or fuzzy strings |
| `make test` | Run the JavaScript unit tests (needs Node.js) |
| `make clean` | Delete the built `.plasmoid`, tarball and `.flatpak` files, the standalone and Flatpak build directories, and the compiled `.mo` files (which are tracked in git; `make translations` regenerates them) |

---

## Configuration

Right-click the widget and select **Configure PlasmaLLM...**:

- **General**: Set your provider, model, and API keys. The **Decisions (TypeSafe / Jev)** adapter (TypeSafe direct or OpenRouter) is for decision models: instead of chatting, each message is evaluated once and answered with a verdict and confidence (Yes / No / Uncertain). Decisions profiles have no conversation memory, system prompt, or tools.
- **Appearance**: Configure fonts, bubble styles, and interface behavior.
- **Tools**: Enable/disable specific tools and configure the filesystem whitelist for sandboxed operations. Finished tool results collapse to a small pill by default (per-tool toggle); click to expand. The `run_command` tool can optionally verify each command with a second model profile before it runs (Auto-detect, Jev/TypeSafe structured decisions, or a JSON verdict from any chat profile): the command must match its LLM-supplied justification and be well-written shell (no incomplete constructs or syntax errors). Mismatched or malformed commands are denied automatically; validation errors fall back to asking for approval. Selecting a Decisions profile as the validator is the recommended setup.
- **Tasks**: Manage custom script tools and shell command templates.
- **Skills**: Discover and toggle Agent Skills (`SKILL.md` folders or `<name>.md` files) loaded on demand. PlasmaLLM ships a bundled `create-skill` helper; add your own under `~/.local/share/plasmallm/skills/` or extra directories in Settings. Skills may include `.sh` scripts run via `run_skill_script`; enable “Allow running skill scripts without approval” per skill in Settings. Use `/skills` in chat to list what is available.

## Support

If you find this widget useful, please consider supporting the [KDE Project](https://kde.org/community/donations/).

## License

This project is licensed under the [GNU General Public License v2.0 or later](LICENSE).

## AI Disclosure

This project was created with extensive use of AI-based tooling.

