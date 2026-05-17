/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library

var name = "http_request";
var description = "Perform an HTTP request (POST, PUT, etc.) to a URL.";
var parameters = {
    type: "object",
    properties: {
        justification: { type: "string", description: "A brief 1 sentence justification for why you are trying to run this command." },
        url: { type: "string", description: "The URL to send the request to" },
        method: { type: "string", description: "HTTP method (GET, POST, PUT, DELETE, etc.)" },
        headers: { type: "object", description: "Optional HTTP headers", additionalProperties: { type: "string" } },
        body: { type: "string", description: "Optional request body" }
    },
    required: ["justification", "url", "method"]
};
var sandboxed = false;
var sideEffect = true;

function execute(args, context) {
    var url = args.url || "";
    if (url.indexOf("http://") !== 0 && url.indexOf("https://") !== 0) {
        context.error(context.i18n("Error: URL must start with http:// or https://"));
        return;
    }
    var max = context.config.toolsHttpMaxBytes || 524288;
    var method = (args.method || "GET").toUpperCase();
    var curlArgs = ["curl -sS --max-time 30 --max-filesize " + max + " -L"];
    curlArgs.push("-X " + method);
    if (args.headers) {
        for (var h in args.headers) {
            curlArgs.push("-H '" + h.replace(/'/g, "'\\''") + ": " + args.headers[h].replace(/'/g, "'\\''") + "'");
        }
    }
    if (args.body) {
        curlArgs.push("-d '" + args.body.replace(/'/g, "'\\''") + "'");
    }
    curlArgs.push("'" + url.replace(/'/g, "'\\''") + "'");
    var cmd = curlArgs.join(" ");
    context.exec(cmd, name, args);
}
