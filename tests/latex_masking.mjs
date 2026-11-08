#!/usr/bin/env node
import fs from "fs";
import path from "path";
import vm from "vm";
import { execFileSync } from "child_process";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, "..");

function loadModule(relPath, extraScope = {}) {
    let code = fs.readFileSync(path.join(__dirname, relPath), "utf8");
    code = code.replace(/^\s*\.(import|pragma)\s+.*$/gm, "");
    const sandbox = { console, ...extraScope };
    vm.createContext(sandbox);
    vm.runInContext(code, sandbox);
    return sandbox;
}

const Api = loadModule("../package/contents/ui/api.js", {
    Adapters: { getAdapter: function() { return {}; } },
    ToolManager: {},
    DriverManager: {},
    WalletCore: {},
    Skills: {},
    Memory: {},
    i18n: function(s) { return s; }
});

let failed = 0;
function eq(actual, expected, msg) {
    if (JSON.stringify(actual) !== JSON.stringify(expected)) {
        failed++;
        console.error("FAIL", msg, "\n  expected:", JSON.stringify(expected),
            "\n  actual:  ", JSON.stringify(actual));
    }
}
function ok(cond, msg) {
    if (!cond) {
        failed++;
        console.error("FAIL", msg);
    }
}

const REPRO = "- **bash:** the same line fails with `syntax error near unexpected token 'uname'` - bash needs `$(...)` or backticks.\n\nOther fish-only examples: `set -x FOO bar` (vs `export`), `$status` instead of `$?`, and `if test -f x; ...; end` - bash uses `fi` instead of `end`.";
const FENCED = "before\n\n```sh\necho $HOME\nprice $$x$$\n```\n\nafter";
const TILDE = "before\n~~~\necho $HOME\n~~~\nafter";
const INLINE_CODE_MATH = "the span `$x^2$` stays literal";
const MATH = "value $x^2$ end";
const CROSSLINE = "costs $5\nand $10";
const ESCAPED = "price \\$5";

const latex = Api.replaceLatexSymbols;

// Literal text: code spans keep their `$`.
eq(latex(REPRO), REPRO, "issue repro: inline code spans untouched");
eq(latex(FENCED), FENCED, "fenced block untouched");
eq(latex(TILDE), TILDE, "tilde fenced block untouched");
eq(latex(INLINE_CODE_MATH), INLINE_CODE_MATH, "inline code span with math untouched");

// Real math still renders.
const mathOut = latex(MATH);
ok(mathOut !== MATH, "real inline math still converted");
eq(mathOut.indexOf("$"), -1, "no dollar delimiters left after conversion");

// A dollar pair split across lines is not a formula.
eq(latex(CROSSLINE), CROSSLINE, "dollars on different lines do not pair");

// Existing escapes keep working.
eq(latex(ESCAPED), "price $5", "escaped dollar still unescaped");

// Block math outside code is still rendered.
ok(latex("$$x^2$$").indexOf("```text") !== -1, "block math still rendered");

// Same cases through the Python renderer. matplotlib is stubbed: these inputs
// contain no formulas that need rendering, and the fallback path is harmless.
const pyScript = `
import sys, os, json, types, importlib.util, tempfile

for name in ("matplotlib", "matplotlib.figure", "matplotlib.backends",
             "matplotlib.backends.backend_agg"):
    sys.modules[name] = types.ModuleType(name)
sys.modules["matplotlib"].use = lambda *a, **k: None

class Figure: pass
class FigureCanvasAgg: pass

sys.modules["matplotlib.figure"].Figure = Figure
sys.modules["matplotlib.backends.backend_agg"].FigureCanvasAgg = FigureCanvasAgg

spec = importlib.util.spec_from_file_location(
    "latex_renderer", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

cases = json.loads(os.environ["PLM_CASES"])
failed = 0
cache = tempfile.mkdtemp()

def run(value):
    return mod.process_text(value, "", cache, 11)

for case in cases["identity"]:
    out = run(case["text"])
    if out != case["text"]:
        failed += 1
        print("FAIL", case["name"], "\\n  expected:", repr(case["text"]),
              "\\n  actual:  ", repr(out))

import contextlib, io
with contextlib.redirect_stderr(io.StringIO()):
    out = run(cases["math"])
if cases["math"] in out:
    failed += 1
    print("FAIL real inline math still converted", repr(out))

out = run(cases["escapedInput"])
if out != cases["escapedOutput"]:
    failed += 1
    print("FAIL escaped dollar still unescaped:", repr(out))

sys.exit(1 if failed else 0)
`;

const pyCases = {
    identity: [
        { name: "issue repro: inline code spans untouched", text: REPRO },
        { name: "fenced block untouched", text: FENCED },
        { name: "tilde fenced block untouched", text: TILDE },
        { name: "inline code span with math untouched", text: INLINE_CODE_MATH },
        { name: "dollars on different lines do not pair", text: CROSSLINE }
    ],
    math: MATH,
    escapedInput: ESCAPED,
    escapedOutput: "price $5"
};

try {
    execFileSync("python3", ["-c", pyScript, path.join(root, "package/contents/ui/latex_renderer.py")], {
        cwd: root,
        encoding: "utf8",
        stdio: ["ignore", "inherit", "inherit"],
        env: { ...process.env, PLM_CASES: JSON.stringify(pyCases) }
    });
} catch (e) {
    failed++;
    console.error("FAIL python renderer assertions");
}

if (failed) {
    console.error(failed + " failure(s)");
    process.exit(1);
}
console.log("latex_masking: ok");
