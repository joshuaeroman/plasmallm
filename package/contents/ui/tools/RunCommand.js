/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

var name = "run_command";
var displayName = "Run Any Terminal Command";
var description = "Execute a shell command on the user's system and return its output.";
var longDescription = "Execute a shell command on the user's system and return its output. " +
    "Guidelines:\n" +
    "- Use `pkexec` instead of `sudo` for any command requiring superuser privileges.\n" +
    "- Chain steps with `&&`.\n" +
    "- Commands run non-interactively. Never use commands that wait for user input (like `read`).\n" +
    "- Use `kdialog` if you need to prompt the user for input or show a message box (e.g., `kdialog --inputbox \"Prompt\"`).\n" +
    "- NEVER install packages, modify system configuration, reboot, or take any action that alters the system or disrupts the user without explicit permission.\n" +
    "- When permission is needed, ask the user in plain text first.\n" +
    "You MUST prefer other, more specific tools (like read_file, write_file, search_files, etc.) if they can accomplish the task. Only use this tool if no other tool is suitable.";
var parameters = {
    type: "object",
    properties: {
        justification: { type: "string", description: "A brief 1 sentence justification for why you are trying to run this command." },
        command: { type: "string", description: "The shell command to execute" }
    },
    required: ["justification", "command"]
};
var sandboxed = false;
var sideEffect = true;
var outputScheme = "console style";

// Helper to wrap commands if session multiplexing is enabled
function wrapCommand(rawCmd, cfg, marker) {
    var be = cfg.sessionMultiplexer === "screen" ? "screen" : "tmux";
    var sess = (cfg.sessionName || "").replace(/[^A-Za-z0-9_-]/g, "") || "plasmallm";
    var heredocDelim = "EOF_PLM_" + marker;

    if (be === "tmux") {
        return `
SESSION='${sess}'
M='${marker}'
OUT=$(mktemp)
CMD_FILE=$(mktemp)
cat << '${heredocDelim}' > "$CMD_FILE"
OUT_FILE="$1"
printf '\\033[1;36m▶ Running command:\\033[0m\\n'
cat << 'EOF_RAW_${marker}'
${rawCmd}
EOF_RAW_${marker}
printf '\\033[1;36m────────────────────────────────────────\\033[0m\\n'
FIFO_DIR=$(mktemp -d)
FIFO="$FIFO_DIR/fifo"
mkfifo "$FIFO"
tee "$OUT_FILE" < "$FIFO" &
TEE_PID=$!
{
${rawCmd}
} >"$FIFO" 2>&1
EXIT_CODE=$?
for i in 1 2 3 4 5; do
    if ! kill -0 $TEE_PID 2>/dev/null; then break; fi
    sleep 0.1
done
kill $TEE_PID 2>/dev/null
wait $TEE_PID 2>/dev/null
rm -rf "$FIFO_DIR"
printf '\\033[1;36m────────────────────────────────────────\\033[0m\\n'
printf '__PLM_DONE_${marker}_%d\\n' "$EXIT_CODE"
${heredocDelim}
tmux has-session -t "\${SESSION}" 2>/dev/null || tmux new-session -d -s "\${SESSION}" -x 200 -y 50
tmux send-keys -t "\${SESSION}":0 ". '\${CMD_FILE}' '\${OUT}'; rm -f '\${CMD_FILE}'" ENTER
while ! tmux capture-pane -t "\${SESSION}":0 -p -S -200 | grep -q "__PLM_DONE_${marker}_"; do sleep 0.1; done
EXIT=\$(tmux capture-pane -t "\${SESSION}":0 -p -S -200 | grep -o "__PLM_DONE_${marker}_[0-9]*" | tail -1 | awk -F_ '{print \$NF}')
cat "\${OUT}"; rm -f "\${OUT}"; rm -f "\${CMD_FILE}"; exit "\${EXIT}"
        `.trim();
    } else {
        return `
SESSION='${sess}'
M='${marker}'
OUT=$(mktemp)
CMD_FILE=$(mktemp)
cat << '${heredocDelim}' > "$CMD_FILE"
OUT_FILE="$1"
printf '\\033[1;36m▶ Running command:\\033[0m\\n'
cat << 'EOF_RAW_${marker}'
${rawCmd}
EOF_RAW_${marker}
printf '\\033[1;36m────────────────────────────────────────\\033[0m\\n'
FIFO_DIR=$(mktemp -d)
FIFO="$FIFO_DIR/fifo"
mkfifo "$FIFO"
tee "$OUT_FILE" < "$FIFO" &
TEE_PID=$!
{
${rawCmd}
} >"$FIFO" 2>&1
EXIT_CODE=$?
for i in 1 2 3 4 5; do
    if ! kill -0 $TEE_PID 2>/dev/null; then break; fi
    sleep 0.1
done
kill $TEE_PID 2>/dev/null
wait $TEE_PID 2>/dev/null
rm -rf "$FIFO_DIR"
printf '\\033[1;36m────────────────────────────────────────\\033[0m\\n'
printf '__PLM_DONE_${marker}_%d\\n' "$EXIT_CODE"
${heredocDelim}
screen -ls "\${SESSION}" | grep -q "\\.\${SESSION}\\b" || { screen -dmS "\${SESSION}"; sleep 0.7; }
screen -S "\${SESSION}" -p 0 -X eval "stuff \\". '\${CMD_FILE}' '\${OUT}'; rm -f '\${CMD_FILE}'\\"" "stuff \\015"
CAP="/tmp/plasmallm-cap-${marker}"
while true; do
    screen -S "\${SESSION}" -p 0 -X hardcopy "\${CAP}"
    if [ -f "\${CAP}" ] && grep -q "__PLM_DONE_${marker}_" "\${CAP}"; then break; fi
    sleep 0.2
done
EXIT=\$(grep -o "__PLM_DONE_${marker}_[0-9]*" "\${CAP}" | tail -1 | awk -F_ '{print \$NF}')
rm -f "\${CAP}"
cat "\${OUT}"; rm -f "\${OUT}"; rm -f "\${CMD_FILE}"; exit "\${EXIT}"
        `.trim();
    }
}

function execute(args, context) {
    var rawCmd = args.command;
    if (!rawCmd) {
        context.error(context.i18n("No command provided."));
        return;
    }

    var marker = Math.random().toString(36).substring(2, 15);
    var wrapped = context.config.useSessionMultiplexer ? wrapCommand(rawCmd, context.config, marker) : rawCmd;
    
    // We pass the raw command as part of args for UI display purposes if needed.
    args._rawCommand = rawCmd;
    args._marker = marker;

    context.exec(wrapped, name, args);
}
