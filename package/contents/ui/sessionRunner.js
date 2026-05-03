.pragma library

function isEnabled(cfg) {
    return cfg.useSessionMultiplexer;
}

function backend(cfg) {
    return cfg.sessionMultiplexer === "screen" ? "screen" : "tmux";
}

function sessionName(cfg) {
    var name = (cfg.sessionName || "").replace(/[^A-Za-z0-9_-]/g, "");
    return name || "plasmallm";
}

function wrapCommand(rawCmd, cfg, marker) {
    var be = backend(cfg);
    var sess = sessionName(cfg);
    var heredocDelim = "EOF_PLM_" + marker;

    if (be === "tmux") {
        return `
SESSION='${sess}'
M='${marker}'
OUT=$(mktemp)
CMD_FILE=$(mktemp)
cat << '${heredocDelim}' > "$CMD_FILE"
OUT_FILE="$1"
{
${rawCmd}
} >"$OUT_FILE" 2>&1
EXIT_CODE=$?
cat << 'EOF_RAW_${marker}'
${rawCmd}
EOF_RAW_${marker}
cat "$OUT_FILE"
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
{
${rawCmd}
} >"$OUT_FILE" 2>&1
EXIT_CODE=$?
cat << 'EOF_RAW_${marker}'
${rawCmd}
EOF_RAW_${marker}
cat "$OUT_FILE"
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

function stopCommand(cfg, marker) {
    var be = backend(cfg);
    var sess = sessionName(cfg);
    if (be === "tmux") {
        return `tmux send-keys -t '${sess}':0 C-c "printf '\\n__PLM_DONE_${marker}_130\\n'" ENTER`;
    } else {
        return `screen -S '${sess}' -p 0 -X eval "stuff \\003" "stuff \\"printf '\\\\n__PLM_DONE_${marker}_130\\\\n'\\\\015\\""`;
    }
}

function killSession(cfg) {
    var be = backend(cfg);
    var sess = sessionName(cfg);
    if (be === "tmux") {
        return `tmux kill-session -t '${sess}'`;
    } else {
        return `screen -S '${sess}' -X quit`;
    }
}
