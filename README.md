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
- **Secure Storage**: Integrates with KWallet for secure management of API keys and secrets.
- **Markdown Rendering**: Full support for markdown, including syntax highlighting for code blocks and LaTeX for mathematical notation.

## Requirements

- KDE Plasma 6.0+
- Qt 6
- Optional: `tmux` or `screen` for session multiplexing.

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

