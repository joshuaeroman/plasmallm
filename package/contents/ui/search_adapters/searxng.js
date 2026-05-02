/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

function performWebSearch(options, query, maxResults, callback) {
    if (!options.searxngUrl || options.searxngUrl.trim() === "") {
        callback("SearXNG URL is not configured", null);
        return;
    }

    var xhr = new XMLHttpRequest();
    // Remove trailing slash if present
    var baseUrl = options.searxngUrl.replace(/\/$/, "");
    var url = baseUrl + "/search?q=" + encodeURIComponent(query) + "&format=json";
    
    if (options.searxngApiKey && options.searxngApiKey.trim() !== "") {
        // Some SearXNG instances use a token query parameter
        url += "&token=" + encodeURIComponent(options.searxngApiKey);
    }
    
    xhr.open("GET", url);
    xhr.timeout = 30000;
    
    // Set headers to look like a browser and avoid some rate limits
    xhr.setRequestHeader("User-Agent", "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
    xhr.setRequestHeader("Accept", "application/json");
    
    if (options.searxngApiKey && options.searxngApiKey.trim() !== "") {
        // Others might expect it as an X-API-Key header
        xhr.setRequestHeader("X-API-Key", options.searxngApiKey);
    }
    
    xhr.ontimeout = function() {
        callback("SearXNG web search timed out", null);
    };

    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText);
                    var results = response.results || [];
                    if (maxResults && maxResults > 0) {
                        results = results.slice(0, maxResults);
                    }
                    var formatted = [];
                    for (var i = 0; i < results.length; i++) {
                        var r = results[i];
                        formatted.push({
                            title: r.title || "",
                            url: r.url || "",
                            snippet: r.content || ""
                        });
                    }
                    callback(null, formatted);
                } catch (e) {
                    callback("Failed to parse SearXNG response: " + e.message, null);
                }
            } else {
                var errMsg = "SearXNG search failed (HTTP " + xhr.status + ")";
                if (xhr.status === 429) {
                    errMsg = "SearXNG reported 'Too Many Requests'. Check your instance rate limits or 'limiter' settings in settings.yml.";
                }
                if (xhr.responseText) {
                    errMsg += ": " + xhr.responseText.substring(0, 200);
                }
                callback(errMsg, null);
            }
        }
    };
    
    xhr.send();
}
