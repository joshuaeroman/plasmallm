/*
    SPDX-FileCopyrightText: 2026 Joshua Roman
    SPDX-License-Identifier: GPL-2.0-or-later
*/

.import "ollama.js" as OllamaSearch
.import "searxng.js" as SearxngSearch
.import "duckduckgo.js" as DuckDuckGoSearch
.import "exa.js" as ExaSearch

function getSearchAdapter(provider) {
    switch (provider) {
    case "exa":
        return ExaSearch;
    case "searxng":
        return SearxngSearch;
    case "duckduckgo":
        return DuckDuckGoSearch;
    case "ollama":
    default:
        return OllamaSearch;
    }
}
