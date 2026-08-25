---
# SPDX-FileCopyrightText: 2026 Joshua Roman
# SPDX-License-Identifier: GPL-2.0-or-later
name: create-skill
description: Interactively create a new PlasmaLLM skill (SKILL.md). Use when the user wants to create a skill, scaffold a skill, write reusable agent instructions, or asks how to add a skill.
---

Create a PlasmaLLM skill on disk. Ask questions in the conversation; do not skip the write.

## 1. Name and purpose

Ask for a skill name, then what it should do.

Validate the name before continuing: lowercase `a-z`, digits, and single hyphens only; must match `^[a-z0-9]+(-[a-z0-9]+)*$`; 1–64 characters (e.g. `weather-report`). If invalid, explain and ask again.

## 2. Environment

Inspect this machine with `run_command` (and `list_dir` / `read_file` if needed): distro and package manager, what is already on PATH, and any relevant config.

Propose concrete helpers for the new skill — existing commands to call, or packages to install if something useful is missing. Confirm with the user, then name those commands/packages in the skill body (and in a `scripts/*.sh` wrapper when the work is a CLI workflow — see step 4).

## 3. Description

Draft a `description` frontmatter value: what the skill does (1–2 sentences) plus trigger phrases the model should match. Show it and let the user edit.

## 4. Write the skill

Path: `~/.local/share/plasmallm/skills/<name>/SKILL.md`. Pass that tilde path to `write_file` as-is — do not expand `~` to `/home/...` (on some systems `$HOME` is a symlink and the absolute form fails the path whitelist). Nested `<name>/SKILL.md` is the default; a flat `<name>.md` in the same folder is also valid. `write_file` creates parent dirs.

Do not overwrite an existing skill without asking.

File format (name must equal the directory name):

```
---
name: <skill-name>
description: <description from step 3>
---

<markdown instructions: steps, commands, and tool use>
```

Keep the body a prompt for the model, not user documentation: concise but thorough — enough steps, commands, and edge cases to run the task, no filler. Specialize to this system when it helps (this distro, package manager, PATH entries, and paths from step 2) instead of generic multi-OS boilerplate. Be specific with trigger words in `description` — that field is how the skill is auto-selected.

If the work is a CLI workflow (download, convert, query a local binary, …), also write a script at `~/.local/share/plasmallm/skills/<name>/scripts/<short>.sh` (tilde path, `write_file`). The script must use `set -euo pipefail`, print usage on bad args, quote `"$@"`, and call the concrete binaries from step 2. `run_skill_script` starts the process in `$HOME` — write outputs under `"$HOME"` (e.g. `"$HOME/Downloads"`) and print the absolute path with `realpath`/`readlink -f`. Prompt-only skills (style, review, writing) do not need a script.

When a script exists, SKILL.md must be enough to call it without reading the `.sh`. List every positional argument and flag (required vs optional, order, example values). Include at least one example `run_skill_script` call with `skill`, `script`, and an `args` array in invocation order — e.g. `args: ["<url>", "0:30", "1:00", "--output", "salmon"]`. Do not document it as a shell command (`download.sh "<url>"`); that is not how the tool is called. Do not tell the model to `read_file` the script first.

`write_file` is limited to the path whitelist (default includes `$HOME`). If the write is blocked, say so and point at Settings → Tools.

## 5. Confirm

Tell the user the skill is ready: it appears in Settings → Skills, the model loads it with the `skill` tool when the description matches, and they can list it with `/skills` (or Refresh in Settings → Skills) to pick up the new file. If you wrote a script, mention they can skip per-run prompts with “Allow running skill scripts without approval” on that skill in Settings → Skills. Do not ask them to grant auto-run in this conversation.
