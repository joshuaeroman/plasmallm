#!/usr/bin/env node
import fs from "fs";
import path from "path";
import vm from "vm";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// Mock QML .import environment
function loadModule(relPath, extraScope = {}) {
    const filePath = path.join(__dirname, relPath);
    let code = fs.readFileSync(filePath, "utf8");
    // Strip QML directives
    code = code.replace(/^\s*\.(import|pragma)\s+.*$/gm, "");
    const sandbox = { console, ...extraScope };
    vm.createContext(sandbox);
    vm.runInContext(code, sandbox);
    return sandbox;
}

// Load adapters
const SpdSay = loadModule("../package/contents/ui/ttsAdapters/spd_say.js");
const OpenaiSpeech = loadModule("../package/contents/ui/ttsAdapters/openai_speech.js");
const CustomCli = loadModule("../package/contents/ui/ttsAdapters/custom_cli.js");

const TtsAdapters = {
    backends: {
        "spd_say": SpdSay,
        "openai_speech": OpenaiSpeech,
        "custom_cli": CustomCli
    },
    get: function(id) {
        return this.backends[id || "spd_say"] || this.backends["spd_say"];
    },
    list: function() {
        return [
            { id: SpdSay.id, name: SpdSay.displayName },
            { id: OpenaiSpeech.id, name: OpenaiSpeech.displayName },
            { id: CustomCli.id, name: CustomCli.displayName }
        ];
    }
};

const Tts = loadModule("../package/contents/ui/tts.js", { TtsAdapters });

let failed = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a !== e) {
        failed++;
        console.error("FAIL", msg, "\n  expected:", e, "\n  actual:  ", a);
    }
}
function ok(cond, msg) {
    if (!cond) {
        failed++;
        console.error("FAIL", msg);
    }
}

// 1. Text Cleaner Tests
const thoughtInput = "<thought>Thinking about answer...</thought>Hello user!";
eq(Tts.cleanTextForSpeech(thoughtInput), "Hello user!", "strip thought tags");

const thinkInput = "<think>Inner reasoning</think>Response text";
eq(Tts.cleanTextForSpeech(thinkInput), "Response text", "strip think tags");

const linkInput = "Check [KDE Website](https://kde.org) for details.";
eq(Tts.cleanTextForSpeech(linkInput), "Check KDE Website for details.", "strip markdown link url");

const shortCodeInput = "Run this command:\n```bash\ngit status\n```";
eq(Tts.cleanTextForSpeech(shortCodeInput), "Run this command: git status", "keep short code snippet");

const longCodeInput = "Here is the implementation:\n```python\n" +
    "def hello():\n" +
    "    print('line 1')\n" +
    "    print('line 2')\n" +
    "    print('line 3')\n" +
    "    print('line 4')\n" +
    "```\nEnjoy!";
eq(Tts.cleanTextForSpeech(longCodeInput), "Here is the implementation: [code block] Enjoy!", "replace long code with [code block]");

const markdownInput = "# Title\n\nThis is **bold** and *italic* and `inline_code`.\n> quote";
eq(Tts.cleanTextForSpeech(markdownInput), "Title. This is bold and italic and inline_code. quote", "clean markdown formatting");

const htmlInput = "<div>Some text &amp; more &lt;code&gt;</div>";
eq(Tts.cleanTextForSpeech(htmlInput), "Some text & more <code>", "strip html tags and decode entities");

// 2. Style / Tone Hint Tests
eq(Tts.applyStyleHint("Hello world", ""), "Hello world", "empty style hint");
eq(Tts.applyStyleHint("Hello world", "<sarcastic>"), "<sarcastic>Hello world</sarcastic>", "tag wrap style hint");
eq(Tts.applyStyleHint("Hello world", "sarcastic"), "<sarcastic>Hello world</sarcastic>", "single word identifier style hint wrapped in tags");
eq(Tts.applyStyleHint("Hello world", "<whisper>"), "<whisper>Hello world</whisper>", "whisper tag wrap");
eq(Tts.applyStyleHint("Hello world", "[in a sarcastic tone: {text}]"), "[in a sarcastic tone: Hello world]", "placeholder replacement");
eq(Tts.applyStyleHint("Hello world", "[whispering]"), "[whispering] Hello world", "prefix style hint");
eq(Tts.applyStyleHint("Hello world", "<speak><prosody rate=\"fast\">{text}</prosody></speak>"),
    "<speak><prosody rate=\"fast\">Hello world</prosody></speak>", "ssml placeholder template");
eq(Tts.applyStyleHint("Hello world", "fake russian voice"), "Hello world", "natural language style hint not prepended to audio");

// Ensure cleaner does not corrupt user style hints when prepared together
const rawResp = "<thought>Pondering</thought># Header\nGreat job on that [bug](http://bug).";
const prepared = Tts.prepareTextForSpeech(rawResp, "<sarcastic>");
eq(prepared, "<sarcastic>Header. Great job on that bug.</sarcastic>", "full pipeline cleans markdown and preserves style tag");

// 3. Known Voices & Presets
const geminiVoices = Tts.knownGeminiVoices();
ok(geminiVoices.length === 30, "30 Gemini voices supported");
ok(geminiVoices.indexOf("Zephyr") >= 0, "Zephyr voice exists");
ok(geminiVoices.indexOf("Puck") >= 0, "Puck voice exists");

const openAiVoices = Tts.knownOpenAiVoices();
ok(openAiVoices.length === 6, "6 OpenAI voices supported");
ok(openAiVoices.indexOf("alloy") >= 0, "alloy voice exists");

const presets = Tts.providerPresets();
const openRouter = presets.find(p => p.name === "OpenRouter");
ok(openRouter, "OpenRouter preset exists");
eq(openRouter.model, "google/gemini-3.8-flash-lite-tts", "OpenRouter default model is Gemini TTS");
eq(openRouter.responseFormat, "pcm", "OpenRouter default response format is pcm");
eq(openRouter.voice, "Zephyr", "OpenRouter default voice is Zephyr");

// 4. Adapters buildCommand
// spd-say
const spdCmd = SpdSay.buildCommand({
    text: "Hello from PlasmaLLM",
    rate: 20,
    pitch: -10,
    voice: "female1",
    language: "en"
});
ok(spdCmd.includes("spd-say"), "spd-say binary in command");
ok(spdCmd.includes("-r 20"), "rate flag included");
ok(spdCmd.includes("-p -10"), "pitch flag included");
ok(spdCmd.includes("-y female1"), "voice flag included");
ok(spdCmd.includes("-l en"), "language flag included");
ok(spdCmd.includes("-e"), "pipe mode flag included");
ok(spdCmd.includes("echo TTS_READY"), "spd-say emits ready signal");

// spd-say stop
const spdStop = SpdSay.buildStopCommand();
ok(spdStop.includes("spd-say -S"), "spd-say stop command");

// openai_speech
const endpointCmd = OpenaiSpeech.buildCommand({
    endpoint: "https://openrouter.ai/api/v1",
    apiKey: "test-key-123",
    model: "google/gemini-3.8-flash-lite-tts",
    voice: "Zephyr",
    responseFormat: "pcm",
    text: "Testing endpoint speech"
});
ok(endpointCmd.includes("https://openrouter.ai/api/v1/audio/speech"), "endpoint audio speech url");
ok(endpointCmd.includes("Authorization: Bearer test-key-123"), "auth header included");
ok(endpointCmd.includes("google/gemini-3.8-flash-lite-tts"), "model in payload");
ok(endpointCmd.includes("python3 -c"), "pcm to wav converter present");
ok(endpointCmd.includes("pw-play"), "pw-play audio player included");
ok(endpointCmd.includes("echo TTS_READY"), "endpoint emits ready signal");

// custom_cli
const customCmd = CustomCli.buildCommand({
    cliTemplate: "piper --model en.onnx --output_raw | pw-play --rate 22050 -",
    text: "Testing piper speech"
});
ok(customCmd.includes("piper --model en.onnx"), "custom template respected");
ok(customCmd.includes("Testing piper speech"), "text appended");
ok(customCmd.includes("echo TTS_READY"), "custom cli emits ready signal");

const customTokenCmd = CustomCli.buildCommand({
    cliTemplate: "espeak-ng -v {voice} -s {rate} {text}",
    voice: "en-us",
    rate: 150,
    text: "Hello"
});
ok(customTokenCmd.includes("espeak-ng -v 'en-us' -s 150 'Hello'"), "tokens replaced properly");
ok(customTokenCmd.includes("echo TTS_READY"), "custom token cli emits ready signal");

// Tts.speak with onReady
let readyTriggered = false;
let callbackTriggered = false;
Tts.speak({
    config: {
        ttsEnabled: true,
        ttsBackend: "spd_say"
    },
    text: "Testing onReady signal",
    onReady: function() {
        readyTriggered = true;
    },
    runCommand: function(cmd, cb, notifyReady) {
        ok(typeof notifyReady === "function", "runCommand receives notifyReady");
        notifyReady();
        cb(null, { stdout: "TTS_READY\n", stderr: "", exitCode: 0 });
    },
    callback: function(err, res) {
        callbackTriggered = true;
        ok(!err, "speak succeeded");
    }
});
ok(readyTriggered, "onReady callback fired when TTS became ready");
ok(callbackTriggered, "completion callback fired");

// Tts.speak onReady fallback on error
let readyOnErrTriggered = false;
Tts.speak({
    config: { ttsEnabled: false },
    text: "Will fail",
    onReady: function() {
        readyOnErrTriggered = true;
    },
    callback: function(err) {
        ok(err, "error returned when TTS not configured");
    }
});
ok(readyOnErrTriggered, "onReady fired even when speak errored out");

// Tts.speak two-phase execution test (synthesize -> onReady -> playback)
let twoPhaseCommands = [];
let twoPhaseReadyFired = false;
let twoPhaseCompleteFired = false;
Tts.speak({
    config: {
        ttsEnabled: true,
        ttsBackend: "openai_speech",
        ttsApiEndpoint: "https://openrouter.ai/api/v1",
        ttsModelName: "google/gemini-3.8-flash-lite-tts",
        ttsVoice: "Zephyr",
        ttsResponseFormat: "pcm"
    },
    text: "Testing two-phase execution timing",
    apiKey: "test-key",
    onReady: function() {
        twoPhaseReadyFired = true;
    },
    runCommand: function(cmd, cb) {
        twoPhaseCommands.push(String(cmd));
        if (twoPhaseCommands.length === 1) {
            // First command: synthesis (curl)
            ok(cmd.includes("curl"), "first command is synthesis/curl");
            ok(!twoPhaseReadyFired, "onReady has NOT fired while synthesis is still downloading");
            // Simulate synthesis completing
            cb(null, { exitCode: 0, stdout: "TTS_READY\n", stderr: "" });
            ok(twoPhaseReadyFired, "onReady FIRED IMMEDIATELY upon synthesis completion before playback");
        } else if (twoPhaseCommands.length === 2) {
            // Second command: playback (pw-play)
            ok(cmd.includes("pw-play"), "second command is playback (pw-play)");
            ok(twoPhaseReadyFired, "onReady was already fired when playback started");
            // Simulate playback finishing
            cb(null, { exitCode: 0, stdout: "", stderr: "" });
        }
    },
    callback: function(err) {
        ok(!err, "two-phase speak completed without error");
        twoPhaseCompleteFired = true;
    }
});
ok(twoPhaseCommands.length === 2, "two distinct commands were executed in sequence");
ok(twoPhaseReadyFired, "onReady fired as soon as audio returned from endpoint");
ok(twoPhaseCompleteFired, "two-phase execution completed");

// 5. fetchModels Tests
// Mock XMLHttpRequest for OpenaiSpeech.fetchModels
function createMockXhr(status, responseData) {
    return function() {
        this.open = function(method, url) { this.url = url; };
        this.setRequestHeader = function(k, v) { this.headers = this.headers || {}; this.headers[k] = v; };
        this.send = function() {
            this.readyState = 4;
            this.status = status;
            this.responseText = typeof responseData === "string" ? responseData : JSON.stringify(responseData);
            if (typeof this.onreadystatechange === "function") {
                this.onreadystatechange();
            }
        };
    };
}

// Successful response with custom TTS models
const MockXhrSuccess = createMockXhr(200, {
    data: [
        { id: "google/gemini-3.8-flash-lite-tts" },
        { id: "openai/tts-1" },
        { id: "my-custom-speech-model" },
        { id: "text-only-model" }
    ]
});

const OpenaiSpeechWithXhr = loadModule("../package/contents/ui/ttsAdapters/openai_speech.js", {
    XMLHttpRequest: MockXhrSuccess
});
OpenaiSpeechWithXhr.fetchModels("https://openrouter.ai/api/v1", "key", function(err, models) {
    ok(!err, "fetchModels succeeded");
    ok(Array.isArray(models), "models is array");
    ok(models.indexOf("google/gemini-3.8-flash-lite-tts") >= 0, "gemini tts in models");
    ok(models.indexOf("my-custom-speech-model") >= 0, "custom speech model discovered");
    ok(models.indexOf("text-only-model") === -1, "text-only model excluded");
});

// Fallback on HTTP error
const MockXhrFail = createMockXhr(500, "Internal Server Error");
const OpenaiSpeechFail = loadModule("../package/contents/ui/ttsAdapters/openai_speech.js", {
    XMLHttpRequest: MockXhrFail
});
OpenaiSpeechFail.fetchModels("https://api.openai.com/v1", "", function(err, models) {
    ok(!err, "fetchModels fallback returns default models on error");
    ok(models.indexOf("google/gemini-3.8-flash-lite-tts") >= 0, "default gemini present");
    ok(models.indexOf("openai/tts-1") >= 0, "default tts-1 present");
});

// Tts coordinator fetchModels dispatch
const TtsWithXhr = loadModule("../package/contents/ui/tts.js", {
    TtsAdapters: {
        get: () => OpenaiSpeechWithXhr
    }
});
TtsWithXhr.fetchModels("https://openrouter.ai/api/v1", "key", "openai_speech", function(err, models) {
    ok(!err, "Tts.fetchModels dispatched successfully");
    ok(models.indexOf("my-custom-speech-model") >= 0, "custom speech model returned through Tts");
});

// 6. System Prompt & buildTtsSection Tests
const mockToolManager = { buildSystemPromptSection: () => "" };
const mockDriverManager = { getDrivingInstructions: () => "" };
const mockWalletCore = loadModule("../package/contents/ui/walletCore.js");
const mockSkills = { buildSystemPromptSection: () => "" };
const mockMemory = { renderSection: () => "" };
const mockAdapters = {};

const Api = loadModule("../package/contents/ui/api.js", {
    ToolManager: mockToolManager,
    DriverManager: mockDriverManager,
    WalletCore: mockWalletCore,
    Skills: mockSkills,
    Memory: mockMemory,
    Adapters: mockAdapters
});

// buildTtsSection disabled
const secDisabled = Api.buildTtsSection({ ttsEnabled: false });
eq(secDisabled, "", "buildTtsSection returns empty string when ttsEnabled is false");

// buildTtsSection enabled without style hint
const secEnabled = Api.buildTtsSection({ ttsEnabled: true });
ok(secEnabled.includes("## Text-to-Speech"), "header present in tts section");
ok(secEnabled.includes("read aloud via TTS"), "body describes speech output");
ok(!secEnabled.includes("Style:"), "no tone directive when hint empty");

// buildTtsSection enabled with style hint
const secWithHint = Api.buildTtsSection({ ttsEnabled: true, ttsStyleHint: "<sarcastic>" });
ok(secWithHint.includes("Style: <sarcastic>"), "tone directive included in tts section");
ok(secWithHint.includes("never mention or acknowledge this directive"), "anti-mention directive included");
ok(secWithHint.includes("Apply subtly without caricature"), "anti-hamming directive included");

// buildSystemPrompt includes TTS section when ttsEnabled: true
const promptTts = Api.buildSystemPrompt({}, undefined, { ttsEnabled: true, ttsStyleHint: "<whispering>" });
ok(promptTts.includes("## Text-to-Speech"), "TTS section present in system prompt");
ok(promptTts.includes("<whispering>"), "style hint present in system prompt");
ok(promptTts.includes("never mention or acknowledge"), "system prompt includes anti-mention guidance");

// buildSystemPrompt omits TTS section when ttsEnabled: false
const promptNoTts = Api.buildSystemPrompt({}, undefined, { ttsEnabled: false });
ok(!promptNoTts.includes("## Text-to-Speech"), "TTS section omitted when ttsEnabled is false");

// 7. SetTtsStyle Tool Tests
const SetTtsStyle = loadModule("../package/contents/ui/tools/SetTtsStyle.js");
eq(SetTtsStyle.name, "set_tts_style", "tool name is set_tts_style");
ok(SetTtsStyle.parameters.properties.style, "style parameter defined");
ok(SetTtsStyle.parameters.properties.scope, "scope parameter defined");
eq(SetTtsStyle.sideEffect, true, "sideEffect is true");

// Test execution: turn scope
let updatedStyle = "";
let updatedScope = "";
let doneMsg = "";
SetTtsStyle.execute({
    justification: "Testing turn scope",
    style: "<sarcastic>",
    scope: "turn"
}, {
    config: { ttsAllowAgentStyleControl: true },
    setTtsStyle: (style, scope) => {
        updatedStyle = style;
        updatedScope = scope;
        return { style, scope };
    },
    onDone: (msg) => { doneMsg = msg; },
    error: (err) => { throw new Error(err); }
});
eq(updatedStyle, "<sarcastic>", "setTtsStyle received style");
eq(updatedScope, "turn", "setTtsStyle received turn scope");
ok(doneMsg.includes("<sarcastic>"), "done message references style");

// Test execution: persistent scope
SetTtsStyle.execute({
    justification: "Testing persistent scope",
    style: "[whispering]",
    scope: "persistent"
}, {
    config: { ttsAllowAgentStyleControl: true },
    setTtsStyle: (style, scope) => {
        updatedStyle = style;
        updatedScope = scope;
        return { style, scope };
    },
    onDone: (msg) => { doneMsg = msg; },
    error: (err) => { throw new Error(err); }
});
eq(updatedStyle, "[whispering]", "persistent style set");
eq(updatedScope, "persistent", "persistent scope set");

// Test execution: gating when disabled
let gatingError = "";
SetTtsStyle.execute({
    justification: "Testing disabled gating",
    style: "<excited>",
    scope: "turn"
}, {
    config: { ttsAllowAgentStyleControl: false },
    setTtsStyle: () => { throw new Error("Should not be called"); },
    onDone: () => { throw new Error("Should not be called"); },
    error: (msg) => { gatingError = msg; }
});
ok(gatingError.includes("disabled"), "error reported when style control disabled in settings");

// 8. ToolManager integration tests
const ToolManager = loadModule("../package/contents/ui/toolManager.js", {
    ToolRegistry: {
        getTool: (n) => n === "set_tts_style" ? SetTtsStyle : null,
        getToolConfigUI: () => "",
        getAllTools: () => [SetTtsStyle]
    },
    DriverManager: { isSessionActive: false },
    Skills: { isSkillScriptAutoRun: () => false },
    i18n: (s) => s
});

// Enabled tools gating
const disabledTools1 = ToolManager.getEnabledTools({
    enableTools: true,
    ttsEnabled: false,
    ttsAllowAgentStyleControl: true
});
ok(disabledTools1.indexOf("set_tts_style") === -1, "set_tts_style disabled when ttsEnabled: false");

const disabledTools2 = ToolManager.getEnabledTools({
    enableTools: true,
    ttsEnabled: true,
    ttsAllowAgentStyleControl: false
});
ok(disabledTools2.indexOf("set_tts_style") === -1, "set_tts_style disabled when ttsAllowAgentStyleControl: false");

const enabledTools = ToolManager.getEnabledTools({
    enableTools: true,
    ttsEnabled: true,
    ttsAllowAgentStyleControl: true
});
ok(enabledTools.indexOf("set_tts_style") >= 0, "set_tts_style enabled when both flags true");

ok(ToolManager.isAutoRun("set_tts_style", {}), "set_tts_style auto-runs without user modal");
eq(ToolManager.toolIconName("set_tts_style"), "audio-volume-high", "set_tts_style uses audio icon");
ok(ToolManager.resultLabel("set_tts_style", { style: "<sarcastic>", scope: "turn" }).includes("<sarcastic>"), "resultLabel formats tone pill");

// 9. Message-level Style Hint & Turn Lifecycle Tests
function resolveStyleHint(overrideStyle, msgIndex, displayMsgs, effectiveHint) {
    if (overrideStyle !== undefined && overrideStyle !== null && String(overrideStyle).length > 0) {
        return String(overrideStyle);
    }
    if (msgIndex !== undefined && msgIndex >= 0 && msgIndex < displayMsgs.length) {
        const m = displayMsgs[msgIndex];
        if (m && m.ttsStyleHint && m.ttsStyleHint.length > 0) {
            return m.ttsStyleHint;
        }
    }
    return effectiveHint || "";
}

const mockDisplayMessages = [
    { role: "user", content: "Say something sarcastic", ttsStyleHint: "" },
    { role: "assistant", content: "Oh brilliant question.", ttsStyleHint: "<sarcastic>" },
    { role: "user", content: "Say something normal", ttsStyleHint: "" },
    { role: "assistant", content: "Sure, here is normal text.", ttsStyleHint: "" }
];

// Replay of message 1 (which was sarcastic): even when current turn style is empty, message 1 uses <sarcastic>
eq(resolveStyleHint(null, 1, mockDisplayMessages, ""), "<sarcastic>", "replaying message uses message-level ttsStyleHint");

// Replay of message 3 (which was normal): uses empty style
eq(resolveStyleHint(null, 3, mockDisplayMessages, ""), "", "replaying normal message uses empty style");

// Explicit override (e.g. from onComplete auto-read) takes precedence
eq(resolveStyleHint("<excited>", 1, mockDisplayMessages, ""), "<excited>", "explicit override takes precedence");

// Fallback to effectiveHint when message has no style
eq(resolveStyleHint(null, 3, mockDisplayMessages, "[whispering]"), "[whispering]", "falls back to effective style hint");

// Tool turn preservation simulation
let turnTtsStyleHint = "";
function handleTurnStart(depth, newStyle) {
    if (depth === 0) {
        turnTtsStyleHint = "";
    }
    if (newStyle) {
        turnTtsStyleHint = newStyle;
    }
}
handleTurnStart(0, "");
eq(turnTtsStyleHint, "", "turn style initially empty");

// Model invokes set_tts_style in Turn 1
handleTurnStart(1, "<sarcastic>");
eq(turnTtsStyleHint, "<sarcastic>", "turn style set by tool");

// Continuation sendToLLM has depth > 0; should NOT clear turnTtsStyleHint
handleTurnStart(1, null);
eq(turnTtsStyleHint, "<sarcastic>", "turn style preserved across tool continuation");

// New user prompt has depth === 0; resets turnTtsStyleHint
handleTurnStart(0, null);
eq(turnTtsStyleHint, "", "turn style reset on new user prompt");

if (failed) {
    console.error(failed + " failure(s)");
    process.exit(1);
}
console.log("tts: ok");
