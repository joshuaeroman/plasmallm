/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.pragma library
.import "../search_adapters/index.js" as SearchAdapters

var name = "web_search";
var displayName = "Web Search";
var icon = "browser-search";
var description = "Perform a web search to find current information, news, or specific facts.";
var parameters = {
    type: "object",
    properties: {
        justification: { type: "string", description: "A brief 1 sentence justification for why you are trying to run this command." },
        query: { type: "string", description: "The search query" },
        max_results: { type: "integer", description: "Maximum number of results to return (default: 5)", minimum: 1, maximum: 10 }
    },
    required: ["justification", "query"]
};
var sandboxed = false;
var sideEffect = false;
var uiHidden = true; // Suppress the default console-style tool output UI block

function formatWebSearchResults(query, results) {
    var text = "🔍 **Web search:** " + query + "\n\n";
    var items = results.results || results;
    if (Array.isArray(items)) {
        for (var i = 0; i < items.length; i++) {
            var r = items[i];
            var title = r.title || r.name || "Result " + (i + 1);
            var snippet = r.snippet || r.description || "";
            // Fall back to content but truncate heavily
            if (!snippet && r.content) {
                snippet = r.content.substring(0, 200).replace(/\n/g, " ").trim();
                if (r.content.length > 200) snippet += "…";
            }
            var url = r.url || r.link || "";
            text += "**" + title + "**\n";
            if (snippet) text += snippet + "\n";
            if (url) text += url + "\n";
            text += "\n";
        }
    } else {
        text += JSON.stringify(results, null, 2);
    }
    return text.trim();
}

function performWebSearch(options, query, maxResults, callback, context) {
    var provider = options.webSearchProvider || "ollama";
    var adapter = SearchAdapters.getSearchAdapter(provider);
    if (adapter && typeof adapter.performWebSearch === "function") {
        adapter.performWebSearch(options, query, maxResults, callback);
    } else {
        callback(context.i18n("Search provider %1 not supported", provider), null);
    }
}

function execute(args, context) {
    var query = args.query || "";
    var maxResults = args.max_results || 5;

    var options = {
        webSearchProvider: context.config.webSearchProvider,
        searxngUrl: context.config.searxngUrl,
        searxngApiKey: context.getSecret("searxngApiKey"),
        ollamaSearchApiKey: context.getSecret("ollamaSearchApiKey")
    };

    if (context.addDisplayMessage) {
        context.addDisplayMessage(context.i18n("Searching the web for: %1…", query), "tool_running_rich", { 
            toolSummary: query,
            toolIcon: icon,
            toolTitle: displayName,
            toolView: "search"
        });
    }

    performWebSearch(options, query, maxResults, function(error, results) {
        if (error) {
            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", error, "error");
            }
            context.onDone("", error, 1);
        } else {
            var displayContent = formatWebSearchResults(query, results);
            var resultsJson = JSON.stringify(results);
            if (context.replaceDisplayMessage) {
                context.replaceDisplayMessage("tool_running_rich", displayContent, "tool_result_rich", {
                    toolSummary: query,
                    toolDataJson: resultsJson,
                    toolView: "search",
                    toolIcon: icon,
                    toolTitle: displayName
                });
            } else if (context.addDisplayMessage) {
                context.addDisplayMessage(displayContent, "tool_result_rich", {
                    toolSummary: query,
                    toolDataJson: resultsJson,
                    toolView: "search",
                    toolIcon: icon,
                    toolTitle: displayName
                });
            }
            context.onDone(resultsJson, "", 0);
        }
    }, context);
}
