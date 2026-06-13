# PlasmaLLM — Tools Documentation

PlasmaLLM features a robust, modular tool-calling system (known as "Tools") that allows LLMs to interact with your system in a controlled, pre-authorized, and secure manner.

## The Tool Architecture

Each tool in PlasmaLLM is a standalone JavaScript module located in `package/contents/ui/tools/`. Tools are registered in `index.js` and follow a standard interface:

- **`name`**: The unique identifier for the tool (e.g., `run_command`).
- **`displayName`**: A human-readable name shown in the UI.
- **`description`**: A detailed description used by the LLM to understand when and how to use the tool.
- **`parameters`**: A JSON Schema defining the arguments the tool accepts.
- **`sandboxed`**: Boolean. If true, the tool's path arguments are checked against the Path Whitelist.
- **`sideEffect`**: Boolean. If true, the tool is considered to have system-altering effects (used to decide when to show UI indicators).
- **`outputScheme`**: Controls how results are rendered (e.g., `"console style"`).
- **`uiHidden`**: Boolean. If true, the tool suppresses the default "Executing..." and "Result" UI blocks. The tool is responsible for providing its own UI feedback if necessary (e.g., via `context.addDisplayMessage`). **Important:** If your tool manually dispatches a custom rich UI card (e.g., role `tool_result_rich`), you *must* set `uiHidden = true` in the module definition; otherwise, the main engine will render its empty default `ToolResultBlock` alongside your custom UI.
- **`execute(args, context)`**: The function called when the LLM invokes the tool.

---

## The Security Model

### 1. Enabling vs. Auto-run
For every tool, you can configure two independent settings:
- **Enabled:** The tool's schema is shared with the LLM. If it requests the tool, the widget will handle it.
- **Auto-run:** If checked, the tool executes immediately. If *not* checked, the widget displays an **Approval Card**, and the tool only runs after you click "Approve". Note that `web_search` is currently hardcoded to auto-run for a seamless search experience.

### 2. Path Sandboxing
Tools marked as `sandboxed` (like `read_file`, `write_file`, `list_dir`, and `search_files`) are restricted to a **Path Whitelist** configured in settings.
- **Validation:** Attempts to access paths outside the whitelist are blocked locally before execution.
- **Expansion:** `~` and `$HOME` are expanded to your actual home directory for execution.
- **Privacy (Redaction):** Before results are sent back to the LLM, all instances of your absolute home path are replaced with `~` to prevent leaking your username.

### 3. Justification
Most system-interacting tools (including `run_command` and all Custom Script Tools) require a `justification` parameter. The LLM must provide a one-sentence explanation of *why* it is running the command, which is displayed on the Approval Card.

### 4. Size Limits
Global safety limits are enforced to prevent context window overflow:
- **Max Read:** Truncates file reads (default 200KB).
- **Max Write:** Rejects writes exceeding the limit (default 1MB).
- **Max HTTP:** Caps network response bodies (default 512KB).

---

## Custom Script Tools

You can extend PlasmaLLM's capabilities by adding your own tools in the **Script Tools** configuration page. These tools run shell commands based on templates you define.

### How to Create a Custom Tool:
1.  **Name:** A unique identifier (e.g., `git_status`).
2.  **Description:** Tell the LLM what this tool does (e.g., "Check the git status of a repository").
3.  **Command Template:** The shell command to run. Use `{curly_braces}` to define parameters the LLM should fill in.
    - *Example:* `git -C {repo_path} status`
4.  **Require Superuser:** If checked, the command will be prefixed with `pkexec` to request root permissions via Polkit.

**Automatic Schema Generation:**
PlasmaLLM automatically parses your `Command Template`, identifies the parameters, and generates a JSON Schema for the LLM. Every custom tool also automatically includes a `justification` parameter.

---

## Tool Reference

### Filesystem Tools
- **`read_file`**: Read file content. (Sandboxed, Max Read Limit)
- **`write_file`**: Create or overwrite a file. (Sandboxed, Side-effect, Max Write Limit)
- **`list_dir`**: List directory contents. (Sandboxed)
- **`search_files`**: Recursive regex search via `grep`. (Sandboxed)

### Network Tools
- **`web_search`**: Perform a web search (DuckDuckGo, SearXNG, or Ollama) to find current facts. This tool uses `uiHidden` to provide rich Markdown results instead of a console block.
- **`http_get`**: Fetch a URL's body. (Max HTTP Limit)
- **`http_request`**: Perform POST, PUT, etc. (Side-effect, Max HTTP Limit)

### Desktop & System Tools
- **`run_command`**: Execute any shell command. This is the most powerful tool and should be used with caution. It supports **Session Multiplexing** (via `tmux` or `screen`) if enabled in settings.
- **`get_clipboard` / `set_clipboard`**: Interact with the system clipboard.
- **`notify`**: Send a system notification via `notify-send`.
- **`open_url`**: Open a URL or file in the default application via `xdg-open`.

### Desktop Automation Tools
- **`StartSession`**: Initializes a Remote Desktop Wayland session and authorization token exchange.
- **`DesktopGetState`**: Unified tool that retrieves the current visual screenshot (optionally cropped to operating context) and the active window list + interactive accessibility element tree.
- **`DesktopSetOperatingContext`**: Binds the LLM's operational context to a specific window UUID, converting coordinates to be window-relative and isolating observation/screenshots.
- **`DesktopResetContext`**: Clears window-specific boundaries and returns the global full-screen state in a single call.
- **`DesktopScroll`**: Simulator for mouse wheel scrolling (up, down, left, right) relative to the active operating context.
- **`DesktopClick` / `DesktopInput` / `DesktopMoveMouse`**: Mouse interaction and text entry tools that automatically adapt coordinates when operating inside an active context window.
- **`DesktopWindowControl`**: Single tool to minimize, maximize, restore, close, or resize/reposition windows using UUIDs.
- **`DesktopReadSelection`**: Triggers a copy keypress sequence and returns the selected text from the clipboard in a single turn.

---

## Visual Styling (Output Schemes)

Tools can specify how their results look in the chat:
- **`"console style"`**: Monospace font, terminal-like black background. Used for `run_command`.
- **`"web_search_results"`**: Rich Markdown formatting with icons and links. Used for `web_search`.
- **`"tool result"` (Default)**: Standard chat bubble.

---

## Developing New Tools

To add a built-in tool, create a new file in `package/contents/ui/tools/` and register it in `index.js`. The `execute` function receives a `context` object with:
- **`config`**: Access to widget configuration.
- **`i18n`**: Function for translating strings.
- **`getSecret(key)`**: Securely retrieve sensitive keys (e.g., `"searxngApiKey"`, `"ollamaSearchApiKey"`).
- **`addDisplayMessage(content, role)`**: Manually push a message to the UI. Useful when `uiHidden` is enabled.
- **`replaceDisplayMessage(oldRole, newContent, newRole)`**: Find the last message with `oldRole` and update its content and role in place. Useful for replacing a "Loading..." indicator with actual results.
- **`exec(command, name, args)`**: Run a shell command.
- **`error(message)`**: Report a failure to the LLM.
- **`onDone(stdout, stderr, exitCode, attachmentsJson)`**: Callback for command completion. Results passed here are sent back to the LLM context. `attachmentsJson` is an optional JSON string containing an array of attachment objects (e.g. data URLs for image confirmation screenshots).

