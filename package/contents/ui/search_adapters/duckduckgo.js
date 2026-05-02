/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

function decodeHtmlEntities(text) {
    if (!text) return "";
    return text.replace(/&amp;/g, "&")
               .replace(/&quot;/g, '"')
               .replace(/&#39;/g, "'")
               .replace(/&#x27;/g, "'")
               .replace(/&lt;/g, "<")
               .replace(/&gt;/g, ">")
               .replace(/&nbsp;/g, " ")
               .replace(/&#(\d+);/g, function(match, dec) {
                   return String.fromCharCode(dec);
               })
               .replace(/&#x([0-9a-f]+);/gi, function(match, hex) {
                   return String.fromCharCode(parseInt(hex, 16));
               });
}

function performWebSearch(options, query, maxResults, callback) {
    var xhr = new XMLHttpRequest();
    var url = "https://lite.duckduckgo.com/lite/";
    
    xhr.open("POST", url);
    xhr.timeout = 30000;
    // Set a generic user-agent and content type for form submission
    xhr.setRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
    xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
    
    xhr.ontimeout = function() {
        callback("DuckDuckGo web search timed out", null);
    };

    xhr.onreadystatechange = function() {
        if (xhr.readyState === XMLHttpRequest.DONE) {
            if (xhr.status === 200) {
                var html = xhr.responseText;
                var results = [];
                
                var linkRegex = /<a[^>]*href="([^"]+)"[^>]*class='result-link'[^>]*>([\s\S]*?)<\/a>/gi;
                var snippetRegex = /<td class='result-snippet'>([\s\S]*?)<\/td>/gi;
                
                var match1, match2;
                // Since the lite version guarantees the snippet follows the link in order, we can step through both
                while ((match1 = linkRegex.exec(html)) !== null && (match2 = snippetRegex.exec(html)) !== null) {
                    var titleStr = decodeHtmlEntities(match1[2].replace(/<[^>]+>/g, "").trim());
                    var urlStr = match1[1].trim();
                    var snippetStr = decodeHtmlEntities(match2[1].replace(/<[^>]+>/g, "").trim());
                    
                    if (urlStr.indexOf("//duckduckgo.com/l/?uddg=") === 0 || urlStr.indexOf("https://duckduckgo.com/l/?uddg=") === 0) {
                        var qPos = urlStr.indexOf("uddg=");
                        if (qPos !== -1) {
                            var endPos = urlStr.indexOf("&", qPos);
                            if (endPos === -1) endPos = urlStr.length;
                            var encodedUrl = urlStr.substring(qPos + 5, endPos);
                            try {
                                urlStr = decodeURIComponent(encodedUrl);
                            } catch(e) {}
                        }
                    } else if (urlStr.indexOf("/") === 0) {
                        urlStr = "https://duckduckgo.com" + urlStr;
                    }
                    
                    results.push({
                        title: titleStr,
                        url: urlStr,
                        snippet: snippetStr
                    });
                }
                
                if (maxResults && maxResults > 0) {
                    results = results.slice(0, maxResults);
                }
                
                if (results.length === 0) {
                    if (html.toLowerCase().indexOf("captcha") !== -1 || html.toLowerCase().indexOf("robot") !== -1) {
                        callback("DuckDuckGo search failed: Blocked by Captcha", null);
                        return;
                    }
                }
                
                callback(null, results);
            } else {
                var errMsg = "DuckDuckGo search failed (HTTP " + xhr.status + ")";
                callback(errMsg, null);
            }
        }
    };
    
    xhr.send("q=" + encodeURIComponent(query));
}
