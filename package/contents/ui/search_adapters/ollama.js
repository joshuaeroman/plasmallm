/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

function performWebSearch(options, query, maxResults, callback) {
    var xhr = new XMLHttpRequest();
    xhr.open("POST", "https://ollama.com/api/web_search");
    xhr.timeout = 30000;
    xhr.setRequestHeader("Content-Type", "application/json");
    if (options.ollamaSearchApiKey) {
        xhr.setRequestHeader("Authorization", "Bearer " + options.ollamaSearchApiKey);
    }

    xhr.ontimeout = function() {
        callback("Web search timed out", null);
    };

    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText);
                    // Ollama returns {results: [...]} usually, pass it along.
                    callback(null, response.results || response);
                } catch (e) {
                    callback("Failed to parse web search response: " + e.message, null);
                }
            } else {
                var errMsg = "Web search failed (HTTP " + xhr.status + ")";
                if (xhr.responseText) {
                    errMsg += ": " + xhr.responseText.substring(0, 200);
                }
                callback(errMsg, null);
            }
        }
    };

    var body = { query: query };
    if (maxResults && maxResults > 0) body.max_results = Math.min(maxResults, 10);
    xhr.send(JSON.stringify(body));
}
