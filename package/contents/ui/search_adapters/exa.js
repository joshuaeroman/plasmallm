/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

function performWebSearch(options, query, maxResults, callback) {
    if (!options.exaApiKey || options.exaApiKey.trim() === "") {
        callback("Exa API key is not configured", null);
        return;
    }

    var searchType = options.exaSearchType || "auto";
    // Deep modes are multi-step research; allow longer than the default 30s.
    var timeoutMs = 30000;
    if (searchType === "deep-reasoning") {
        timeoutMs = 120000;
    } else if (searchType === "deep") {
        timeoutMs = 90000;
    } else if (searchType === "deep-lite" || searchType.indexOf("deep") === 0) {
        timeoutMs = 60000;
    }

    var xhr = new XMLHttpRequest();
    xhr.open("POST", "https://api.exa.ai/search");
    xhr.timeout = timeoutMs;
    xhr.setRequestHeader("Content-Type", "application/json");
    xhr.setRequestHeader("x-api-key", options.exaApiKey.trim());

    xhr.ontimeout = function() {
        callback("Exa web search timed out", null);
    };

    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText);
                    var rawResults = response.results || [];
                    if (maxResults && maxResults > 0) {
                        rawResults = rawResults.slice(0, maxResults);
                    }
                    var formatted = [];
                    for (var i = 0; i < rawResults.length; i++) {
                        var r = rawResults[i];
                        var snippetStr = "";
                        if (Array.isArray(r.highlights) && r.highlights.length > 0) {
                            snippetStr = r.highlights.join("\n… ");
                        } else if (r.snippet) {
                            snippetStr = r.snippet;
                        } else if (r.summary) {
                            snippetStr = String(r.summary).substring(0, 300);
                        } else if (r.text) {
                            snippetStr = r.text.substring(0, 300);
                        }
                        formatted.push({
                            title: r.title || r.url || "",
                            url: r.url || "",
                            snippet: snippetStr
                        });
                    }
                    callback(null, formatted);
                } catch (e) {
                    callback("Failed to parse Exa response: " + e.message, null);
                }
            } else {
                var errMsg = "Exa search failed (HTTP " + xhr.status + ")";
                if (xhr.responseText) {
                    errMsg += ": " + xhr.responseText.substring(0, 200);
                }
                callback(errMsg, null);
            }
        }
    };

    var body = {
        query: query,
        type: searchType,
        numResults: maxResults || 5,
        contents: {
            highlights: true,
            text: { maxCharacters: 300 }
        }
    };
    xhr.send(JSON.stringify(body));
}
