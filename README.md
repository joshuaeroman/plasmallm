# PlasmaLLM

PlasmaLLM is a system-aware AI assistant widget for the KDE Plasma 6 desktop. It provides a native interface to various LLM endpoints, integrating system information gathering, web search, and shell command execution directly into your desktop workflow.

![License: GPL-2.0-or-later](https://img.shields.io/badge/License-GPL--2.0--or--later-blue.svg)
![KDE Plasma 6](https://img.shields.io/badge/Plasma-6.0%2B-blue)
![Qt 6](https://img.shields.io/badge/Qt-6.0%2B-green)

PlasmaLLM is designed for quick tasks and system-integrated workflows—not as a replacement for full-featured chat applications. It excels at answering technical questions about your system, running terminal commands, and providing an agentic interface for desktop automation.

## Features

- **Multi-Provider Support**: Connects to Ollama, LM Studio, OpenAI, Anthropic Claude, Google Gemini, and any OpenAI-compatible API.
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

---

## Configuration

Right-click the widget and select **Configure PlasmaLLM...**:

- **General**: Set your provider, model, and API keys.
- **Appearance**: Configure fonts, bubble styles, and interface behavior.
- **Tools**: Enable/disable specific tools and configure the filesystem whitelist for sandboxed operations.
- **Tasks**: Manage custom script tools and shell command templates.

## Support

If you find this widget useful, please consider supporting the [KDE Project](https://kde.org/community/donations/).

## License

This project is licensed under the [GNU General Public License v2.0 or later](LICENSE).

## AI Disclosure

This project was created with extensive use of AI-based tooling.

