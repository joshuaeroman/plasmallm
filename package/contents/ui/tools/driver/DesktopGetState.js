/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library
.import "../../driverManager.js" as DriverManager

var name = "DesktopGetState";
var displayName = "Desktop Get State";
var description = "Captures the visual screenshot and extracts the active window lists and interactive accessibility tree coordinates (0-1000 scale). Caches current window positions and active operating context.";
var parameters = {
    type: "object",
    properties: {
        observation: { type: "string", description: "What you see on the screen." },
        pending_tasks: { type: "string", description: "What you still need to do." },
        planned_actions: { type: "string", description: "What you plan to do." },
        include_tree: { type: "boolean", description: "Whether to query and include the accessibility element tree. Defaults to true." }
    },
    required: ["observation", "pending_tasks", "planned_actions"]
};
var sandboxed = false;
var sideEffect = false;
var uiHidden = true;

function execute(args, context) {
    var thinkingStr = "";
    if (args.observation) thinkingStr += "\n\n**Observation:** " + args.observation;
    if (args.pending_tasks) thinkingStr += "\n\n**Pending Tasks:** " + args.pending_tasks;
    if (args.planned_actions) thinkingStr += "\n\n**Planned Actions:** " + args.planned_actions;
    var baseMsg = "**Action:** Get desktop state" + thinkingStr;

    if (context.addDisplayMessage) {
        context.addDisplayMessage(baseMsg + "\n\n*Retrieving visual and semantic desktop state...*", "tool_running_rich", {
            toolSummary: "Querying Desktop State",
            toolIcon: "video-display",
            toolTitle: displayName
        });
    }

    var params = { include_tree: args.include_tree !== false };

    var path = DriverManager.getNewScreenshotPath();
    if (path) {
        params.save_path = path;
    }

    DriverManager.executeCommand("get_desktop_state", params, function(err, result) {
        if (err) {
            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", err, "error");
            }
            context.onDone("", err, 1);
        } else {
            var atts = [];
            var attachmentsStr = "";
            if (result.image) {
                atts = [{ filePath: result.image, fileName: "screenshot.jpg" }];
                attachmentsStr = result.image;
            }

            var windowsData = result.windows || [];
            var treeData = result.accessibility_tree || [];
            var formattedResult = "Unified Desktop State:\n\n";
            
            var activeContextOrd = DriverManager.getActiveContext();
            if (activeContextOrd) {
                formattedResult += "**Active Operating Context Window**: `" + activeContextOrd + "`\n\n";
            } else {
                formattedResult += "**Active Operating Context**: Global Desktop\n\n";
            }
            
            if (windowsData.length > 0) {
                formattedResult += "### Open Windows:\n";
                for (var i = 0; i < windowsData.length; i++) {
                    var win = windowsData[i];
                    var stateStr = " [Minimized: " + (win.minimized ? "Yes" : "No") + 
                                   ", Active: " + (win.active ? "Yes" : "No") + 
                                   ", On Current Desktop: " + (win.on_current_desktop ? "Yes" : "No") + "]";
                    formattedResult += "- **" + win.title + "** (Window ID: `" + win.uuid + "`)" + stateStr + "\n";
                    formattedResult += "  - Normalized 0-1000 Bounds:\n";
                    formattedResult += "    - X: " + win.normalized_bounds.left_nx + " to " + win.normalized_bounds.right_nx + "\n";
                    formattedResult += "    - Y: " + win.normalized_bounds.top_ny + " to " + win.normalized_bounds.bottom_ny + "\n";
                    formattedResult += "    - Center: (" + win.normalized_bounds.center_nx + ", " + win.normalized_bounds.center_ny + ")\n";
                    formattedResult += "    - Window ID: `" + win.uuid + "`\n";
                }
                formattedResult += "\n";
            }
            
            if (treeData.length > 0) {
                formattedResult += "### Accessibility Tree (Interactive Elements):\n";
                for (var j = 0; j < treeData.length; j++) {
                    var elem = treeData[j];
                    formattedResult += "- [" + elem.role + "] Name: '" + elem.name + "' Bounds: " + 
                                       "X: " + elem.bounds.left_nx + " to " + elem.bounds.right_nx + ", " +
                                       "Y: " + elem.bounds.top_ny + " to " + elem.bounds.bottom_ny + " Center: (" + 
                                       elem.bounds.center_nx + ", " + elem.bounds.center_ny + ")\n";
                }
            } else {
                formattedResult += "### Accessibility Tree: No interactive elements detected.";
            }

            var userMsg = baseMsg + "\n\n*Desktop state retrieved.*";
            var llmMsg = baseMsg + "\n\n*NOTE: Your mouse pointer is currently positioned exactly in the middle of the attached screenshot. You may call a click action with NO coordinates to click the exact center of this image.*\n\n*" + formattedResult + "*";

            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", userMsg, "tool_result_rich", {
                    toolSummary: "Desktop State Retrieved",
                    toolDataJson: JSON.stringify({ window_count: windowsData.length }),
                    toolIcon: "video-display",
                    toolTitle: displayName,
                    attachmentsStr: attachmentsStr
                });
            }
            context.onDone(JSON.stringify({ status: "success", detail: llmMsg }), "", 0, JSON.stringify(atts));
        }
    });
}
