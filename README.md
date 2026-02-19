# PlasmaLLM

A KDE Plasma 6 widget that provides a chat interface to OpenAI-compatible LLM endpoints. Integrates system information gathering, markdown rendering, and shell command execution directly from the desktop.

![License: GPL-2.0-or-later](https://img.shields.io/badge/License-GPL--2.0--or--later-blue.svg)

PlasmaLLM is designed for quick questions and system tasks right from your panel — not as a full-featured AI chat application. Think of it as a handy assistant for looking things up, running commands, and getting help with your system without leaving the desktop.

## Features

- Chat with any OpenAI-compatible API (Ollama, LM Studio, OpenAI, Anthropic, Groq, and more)
- System-aware: automatically gathers hardware and OS info for contextual responses
- Interactive command blocks: run, copy, save, or open suggested shell commands in a terminal
- Markdown rendering for assistant responses
- Auto-run and auto-share modes for agentic workflows
- Chat history auto-save
- Configurable provider presets, temperature, max tokens, and custom system prompts

<img width="514" height="582" alt="image" src="https://github.com/user-attachments/assets/0ab720f7-786c-4975-b88c-f54ab5716efd" />

## Requirements

- KDE Plasma 6.0+
- Qt 6

No external dependencies — uses only Qt and KDE Plasma APIs.

## Installation

### From GitHub Releases (recommended)

Download the latest `.plasmoid` file from the [Releases](https://github.com/joshuaeroman/plasmallm/releases) page, then install it:

```bash
plasmapkg2 --install PlasmaLLM-*.plasmoid
```

Or right-click your desktop → **Add Widgets** → **Get New Widgets** → **Install from Local File**.

Then restart Plasma:

```bash
plasmashell --replace &
```

### From Source

Clone the repository and run the install script:

```bash
git clone https://github.com/joshuaeroman/plasmallm.git
cd plasmallm
./install.sh
plasmashell --replace &
```

For development (symlinks the package directory so changes apply on Plasma restart instead of requiring a reinstall):

```bash
./install.sh --dev
```

To uninstall:

```bash
./install.sh --remove
```

### Building a `.plasmoid` from Source

`package.sh` zips the `package/` directory into a versioned `.plasmoid` file (a standard KDE widget archive):

```bash
./package.sh
# Creates e.g. PlasmaLLM-x.y.z.plasmoid
```

Requires `python3` (to read the version from `metadata.json`) and `zip`.

## Configuration

Right-click the widget and open **Configure...**. Settings include:

- **Provider**: choose a preset (Ollama, LM Studio, OpenAI, etc.) or enter a custom endpoint
- **Model**: select from available models via "Fetch Models" or type manually
- **API Key**: required for cloud providers
- **Temperature / Max Tokens**: control response behavior
- **Auto-save chat history**: saves conversations to `~/PlasmaLLM/chats/`
- **Auto-run commands**: automatically executes shell commands from LLM responses
- **Auto-share command output**: sends command output back to the LLM (enables agentic loops when combined with auto-run)
- **Custom system prompt**: appended to the built-in prompt with highest precedence

## Support

If you find this useful, consider donating to [KDE](https://kde.org/community/donations/) — the project that makes all of this possible.

## License

This project is licensed under the [GNU General Public License v2.0 or later](LICENSE).

Vibe-coded with 🤖
