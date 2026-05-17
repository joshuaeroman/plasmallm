/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

var name = "http_get";
var description = "Perform an HTTP GET request to a URL and return the response content.";
var parameters = {
    type: "object",
    properties: {
        justification: { type: "string", description: "A brief 1 sentence justification for why you are trying to run this command." },
        url: { type: "string", description: "The URL to fetch (must start with http:// or https://)" }
    },
    required: ["justification", "url"]
};
var sandboxed = false;
var sideEffect = false;

function execute(args, context) {
    var url = args.url || "";
    if (url.indexOf("http://") !== 0 && url.indexOf("https://") !== 0) {
        context.error(context.i18n("Error: URL must start with http:// or https://"));
        return;
    }
    var max = context.config.toolsHttpMaxBytes || 524288;
    var cmd = "curl -sS --max-time 30 --max-filesize " + max + " -L '" + url.replace(/'/g, "'\\''") + "'";
    context.exec(cmd, name, args);
}
