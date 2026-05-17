/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

var name = "open_url";
var description = "Open a URL in the default application (e.g., web browser).";
var parameters = {
    type: "object",
    properties: {
        justification: { type: "string", description: "A brief 1 sentence justification for why you are trying to run this command." },
        url: { type: "string", description: "The URL to open (must start with http:// or https://)" }
    },
    required: ["justification", "url"]
};
var sandboxed = false;
var sideEffect = true;

function execute(args, context) {
    var url = args.url || "";
    if (url.indexOf("http://") !== 0 && url.indexOf("https://") !== 0) {
        context.error(context.i18n("Error: URL must start with http:// or https://"));
        return;
    }
    var cmd = "xdg-open '" + url.replace(/'/g, "'\\''") + "'";
    context.exec(cmd, name, args);
}
