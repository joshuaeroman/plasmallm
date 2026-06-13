/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library
.import "../../driverManager.js" as DriverManager

var name = "DesktopMoveMouse";
var displayName = "Desktop Move Mouse";
var description = "Move the mouse pointer. Coordinates are relative to the active operating context window (if set via DesktopSetOperatingContext), or absolute screen coordinates otherwise.";
var parameters = {
    type: "object",
    properties: {
        observation: { type: "string", description: "What you see on the screen." },
        pending_tasks: { type: "string", description: "What you still need to do." },
        planned_actions: { type: "string", description: "What you plan to do." },
        nx: { type: "number", description: "X coordinate (0-1000). Relative to the active operating context window (0=left edge, 500=center, 1000=right edge) if set; absolute screen coordinate otherwise." },
        ny: { type: "number", description: "Y coordinate (0-1000). Relative to the active operating context window (0=top edge, 500=center, 1000=bottom edge) if set; absolute screen coordinate otherwise." },
        zoom: { type: "string", description: "Zoom level for confirmation crop: 'tight' or 'precise'. Defaults to 'tight'.", enum: ["tight", "precise"] }
    },
    required: ["observation", "pending_tasks", "planned_actions", "nx", "ny"]
};
var sandboxed = false;
var sideEffect = true;
var uiHidden = true;

function execute(args, context) {
    if (JSON.stringify(args).indexOf("__CANCEL__") !== -1) {
        context.addDisplayMessage("Action safely cancelled by LLM (__CANCEL__).", "error");
        context.onDone(JSON.stringify({ status: "cancelled", detail: "Action safely cancelled because __CANCEL__ was detected in your arguments. You may now take your next turn." }), "", 0);
        return;
    }

    var method = "move_mouse";
    if (args.nx === undefined || args.ny === undefined) {
        context.addDisplayMessage("Action blocked: Missing coordinates. You must provide both absolute coordinates nx and ny.", "error");
        context.onDone(JSON.stringify({ status: "error", message: "You must provide both absolute coordinates nx and ny." }), "", 0);
        return;
    }

    var params = {
        zoom: args.zoom || "tight",
        nx: args.nx,
        ny: args.ny
    };
    DriverManager.lastZoom = params.zoom;

    var pathAfter = DriverManager.getNewScreenshotPath();
    if (pathAfter) {
        params.save_paths = [pathAfter, ""];
    }

    var details = "Move mouse to (" + args.nx + "," + args.ny + ")";


    var thinkingStr = "";
    if (args.observation) thinkingStr += "\n\n**Observation:** " + args.observation;
    if (args.pending_tasks) thinkingStr += "\n\n**Pending Tasks:** " + args.pending_tasks;
    if (args.planned_actions) thinkingStr += "\n\n**Planned Actions:** " + args.planned_actions;
    var baseMsg = "**Action:** " + details + thinkingStr;

    var displayParams = JSON.parse(JSON.stringify(params));

    if (context.addDisplayMessage) {
        context.addDisplayMessage(baseMsg + "\n\n*Emulating action...*", "tool_running_rich", {
            toolSummary: "mouse move event",
            toolIcon: "input-mouse",
            toolTitle: displayName
        });
    }
    DriverManager.executeCommand(method, params, function(err, result) {
        if (err) {
            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", err, "error");
            }
            context.onDone("", err, 1);
        } else {
            var userMsg = baseMsg + "\n\n*Action executed.*";
            var llmMsg = baseMsg + "\n\n*Action executed. A confirmation crop image is attached — does the pointer target the correct control? NOTE: Your mouse pointer is currently positioned exactly in the middle of this image. If it aligns perfectly, proceed to call DesktopClick with NO coordinates to click the exact center of this image.*\n\n> [!TIP]\n> You can click/type directly, or call DesktopMoveMouse to verify pointer alignment. If you get lost and need to see the full screen again, use the DesktopGetState tool.";
            DriverManager.lastDesktopMoveTime = Date.now();
            var images = (result && Array.isArray(result.images)) ? result.images : [];
            var atts = [];
            var attachmentsStr = "";
            var attachDataUrls = [];
            var filenames = ["after.jpg"];
            for (var i = 0; i < images.length; i++) {
                if (images[i]) {
                    atts.push({ filePath: images[i], fileName: (filenames[i] || "image.jpg") });
                    attachDataUrls.push(images[i]);
                }
            }
            attachmentsStr = attachDataUrls.join("\n");

            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", userMsg, "tool_result_rich", {
                    toolSummary: "mouse moved",
                    toolDataJson: JSON.stringify(displayParams),
                    toolIcon: "input-mouse",
                    toolTitle: displayName,
                    attachmentsStr: attachmentsStr
                });
            }
            context.onDone(JSON.stringify({ status: "success", detail: llmMsg }), "", 0, JSON.stringify(atts));
        }
    });
}
