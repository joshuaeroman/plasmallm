# PlasmaLLM

A KDE Plasma 6 widget providing a chat interface to various LLM endpoints (OpenAI, Anthropic, Gemini, Ollama, etc.) with system awareness and interactive command execution.

## Project Overview

- **Technologies:** QML, JavaScript, Qt 6, KDE Plasma 6.
- **Architecture:** 
  - `package/contents/ui/main.qml`: Main entry point and state management.
  - `package/contents/ui/api.js`: Provider-neutral API logic and coordination.
  - `package/contents/ui/adapters/`: Provider-specific implementations (OpenAI, Anthropic, Gemini).
  - `package/contents/ui/FullRepresentation.qml`: Main UI layout.
  - `package/contents/ui/ChatMessage.qml`: Rendering of individual chat messages and command blocks.
  - `package/contents/locale/`: Internationalization (PO/MO files).

## Building and Running

The project uses a `Makefile` for common development tasks.

- **Install for development (Symlink):**
  ```bash
  make install-dev
  plasmashell --replace &
  ```
- **Install (Copy):**
  ```bash
  make install
  plasmashell --replace &
  ```
- **Build `.plasmoid` package:**
  ```bash
  make package
  ```
- **Update and compile translations:**
  ```bash
  make translations
  ```
- **Uninstall:**
  ```bash
  make remove
  ```

## Development Conventions

- **I18N:** Use `i18n()` for user-facing strings in QML/JS. Update `.po` files via `make translations`.
- **API Adapters:** New LLM providers should be added as a module in `package/contents/ui/adapters/` and registered in `package/contents/ui/adapters/index.js`.
- **System Commands:** The widget uses `P5Support.DataSource` (engine: "executable") to run shell commands. Ensure commands are non-interactive.
- **Styling:** Adheres to Kirigami and Plasma components for a native Look and Feel.
- **Version Management:** Versioning is handled in `package/metadata.json`. The `make package` command prompts for a new version.

## Key Files

- `package/metadata.json`: Widget metadata and versioning.
- `package/contents/config/main.xml`: Configuration schema for the widget.
- `package/contents/ui/main.qml`: Core logic for chat flow, system info gathering, and command execution.
- `package/contents/ui/api.js`: Core API orchestration.
- `package/contents/ui/adapters/*.js`: LLM provider integrations.
