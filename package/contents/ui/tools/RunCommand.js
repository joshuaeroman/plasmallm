/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

var name = "plm_run_command";
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
    "- For auto-run tools: Be conservative and prefer read-only commands. If an action is potentially disruptive, describe it in plain text and wait for explicit user approval before calling the tool.\n" +
    "- You MUST prefer other, more specific tools (like plm_read_file, plm_write_file, plm_search_files, etc.) if they can accomplish the task. Only use this tool if no other tool is suitable.";
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
if ! tmux has-session -t "\${SESSION}" 2>/dev/null; then
    tmux new-session -d -s "\${SESSION}" -x 200 -y 50
fi
for _i in 1 2 3 4 5 6 7 8 9 10; do
    PANE_SHELL=\$(tmux display-message -p -t "\${SESSION}:" '#{pane_current_command}' 2>/dev/null)
    case "\${PANE_SHELL}" in
        ""|tmux) sleep 0.05 ;;
        *) break ;;
    esac
done
if [ "\${PANE_SHELL}" = "fish" ]; then
    RAW_FILE=\$(mktemp)
    cat << 'EOF_RAW_${marker}' > "$RAW_FILE"
${rawCmd}
EOF_RAW_${marker}
    cat << '${heredocDelim}' > "$CMD_FILE"
set _plm_out "$argv[1]"
set _plm_raw "$argv[2]"
printf '\\033[1;36m▶ Running command:\\033[0m\\n'
cat "$_plm_raw"
printf '\\033[1;36m────────────────────────────────────────\\033[0m\\n'
set _plm_fifo_dir (mktemp -d)
set _plm_fifo "$_plm_fifo_dir/fifo"
mkfifo "$_plm_fifo"
sh -c 'tee "$1" < "$2"' _ "$_plm_out" "$_plm_fifo" &
set _plm_tee_pid $last_pid
begin
    fish -n "$_plm_raw"; and source "$_plm_raw"
end >"$_plm_fifo" 2>&1
set _plm_exit $status
for _plm_i in 1 2 3 4 5
    if not kill -0 $_plm_tee_pid 2>/dev/null; break; end
    sleep 0.1
end
kill $_plm_tee_pid 2>/dev/null
wait $_plm_tee_pid 2>/dev/null
rm -rf "$_plm_fifo_dir"
printf '\\033[1;36m────────────────────────────────────────\\033[0m\\n'
printf '__PLM_DONE_${marker}_%d\\n' "$_plm_exit"
${heredocDelim}
    PCMD="source '\${CMD_FILE}' '\${OUT}' '\${RAW_FILE}'; rm -f '\${CMD_FILE}' '\${RAW_FILE}'"
else
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
    case "\${PANE_SHELL}" in
        bash|zsh|ksh|dash|sh) PCMD=". '\${CMD_FILE}' '\${OUT}'; rm -f '\${CMD_FILE}'" ;;
        *) PCMD="bash '\${CMD_FILE}' '\${OUT}'; rm -f '\${CMD_FILE}'" ;;
    esac
fi
tmux send-keys -t "\${SESSION}:" "\${PCMD}" ENTER
while ! tmux capture-pane -t "\${SESSION}:" -p -S -200 | grep -q "__PLM_DONE_${marker}_"; do sleep 0.1; done
EXIT=\$(tmux capture-pane -t "\${SESSION}:" -p -S -200 | grep -o "__PLM_DONE_${marker}_[0-9]*" | tail -1 | awk -F_ '{print \$NF}')
cat "\${OUT}"; rm -f "\${OUT}" "\${CMD_FILE}" "\${RAW_FILE}"; exit "\${EXIT}"
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
