#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Joshua Roman
# SPDX-License-Identifier: GPL-2.0-or-later

import os
import sys
import re
import hashlib

# 1. Check matplotlib availability. Exit with code 3 if missing.
try:
    import matplotlib
    matplotlib.use('Agg')
    from matplotlib.figure import Figure
    from matplotlib.backends.backend_agg import FigureCanvasAgg
except ImportError:
    sys.stderr.write("Error: matplotlib is not installed. Please install it using your package manager (e.g. python3-matplotlib) or pip.\n")
    sys.exit(3)

# GREEK LETTERS AND MATH SYMBOLS FOR LATEX CHARACTER REPLACEMENT (Fallback)
GREEK_LOWER = {
    "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
    "zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ",
    "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "pi": "π",
    "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ",
    "chi": "χ", "psi": "ψ", "omega": "ω", "varepsilon": "ϵ", "vartheta": "ϑ",
    "varphi": "ϕ"
}

GREEK_UPPER = {
    "Alpha": "Α", "Beta": "Β", "Gamma": "Γ", "Delta": "Δ", "Epsilon": "Ε",
    "Zeta": "Ζ", "Eta": "Η", "Theta": "Θ", "Iota": "Ι", "Kappa": "Κ",
    "Lambda": "Λ", "Mu": "Μ", "Nu": "Ν", "Xi": "Ξ", "Pi": "Π",
    "Rho": "Ρ", "Sigma": "Σ", "Tau": "Τ", "Upsilon": "Υ", "Phi": "Φ",
    "Chi": "Χ", "Psi": "Ψ", "Omega": "Ω"
}

MATH_SYMBOLS = {
    "infty": "∞", "pm": "±", "times": "×", "div": "÷", "neq": "≠",
    "leq": "≤", "geq": "≥", "approx": "≈", "equiv": "≡", "cong": "≅",
    "propto": "∝", "partial": "∂", "nabla": "∇", "sum": "∑", "prod": "∏",
    "int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮", "forall": "∀",
    "exists": "∃", "emptyset": "∅", "in": "∈", "notin": "∉", "subset": "⊂",
    "supset": "⊃", "subseteq": "⊆", "supseteq": "⊇", "cup": "∪", "cap": "∩",
    "cdot": "·", "sqrt": "√", "hbar": "ℏ", "rightarrow": "→", "to": "→",
    "leftarrow": "←", "uparrow": "↑", "downarrow": "↓", "leftrightarrow": "↔",
    "Rightarrow": "⇒", "Leftarrow": "⇐", "Leftrightarrow": "⇔",
    "sin": "sin", "cos": "cos", "tan": "tan", "log": "log", "ln": "ln",
    "deg": "°", "partial": "∂"
}

SUPERSCRIPTS = {
    "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
    "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "x": "ˣ", "y": "ʸ", "i": "ⁱ", "j": "ʲ"
}

SUBSCRIPTS = {
    "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
    "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "o": "ₒ", "x": "ₓ", "i": "ᵢ", "j": "ⱼ"
}

def fallback_replace_formula(formula):
    # Simplify \frac
    def rep_frac(m):
        return f"({m.group(1)})/({m.group(2)})"
    
    formula = re.sub(r'\\frac\s*\{([^}]*)\}\s*\{([^}]*)\}', rep_frac, formula)
    
    # Superscripts
    def rep_super_curly(m):
        return "".join(SUPERSCRIPTS.get(c, c) for c in m.group(1))
    formula = re.sub(r'\^\{([^}]*)\}', rep_super_curly, formula)
    
    def rep_super_single(m):
        return SUPERSCRIPTS.get(m.group(1), f"^{m.group(1)}")
    formula = re.sub(r'\^([0-9a-zA-Z\+\-\(\)])', rep_super_single, formula)
    
    # Subscripts
    def rep_sub_curly(m):
        return "".join(SUBSCRIPTS.get(c, c) for c in m.group(1))
    formula = re.sub(r'_\{([^}]*)\}', rep_sub_curly, formula)
    
    def rep_sub_single(m):
        return SUBSCRIPTS.get(m.group(1), f"_{m.group(1)}")
    formula = re.sub(r'_([0-9a-zA-Z\+\-\(\)])', rep_sub_single, formula)
    
    # Greek and symbols
    def rep_cmd(m):
        cmd = m.group(1)
        if cmd in GREEK_LOWER: return GREEK_LOWER[cmd]
        if cmd in GREEK_UPPER: return GREEK_UPPER[cmd]
        if cmd in MATH_SYMBOLS: return MATH_SYMBOLS[cmd]
        return cmd
    formula = re.sub(r'\\([a-zA-Z]+)', rep_cmd, formula)
    
    # Clean up braces and backslashes
    formula = formula.replace('{', '').replace('}', '').replace('\\', '')
    return formula.strip()

def recolor_svg(svg_path, color_hex):
    """
    Modifies the SVG file's black stroke/fill elements to match the target color_hex.
    """
    if not color_hex:
        return
    
    if not color_hex.startswith('#'):
        color_hex = '#' + color_hex
        
    try:
        with open(svg_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Replace occurrences of #000000 (black) with the target color
        content = content.replace('#000000', color_hex)
        content = content.replace('fill="#000000"', f'fill="{color_hex}"')
        content = content.replace('stroke="#000000"', f'stroke="{color_hex}"')
        content = content.replace('fill: #000000', f'fill: {color_hex}')
        content = content.replace('stroke: #000000', f'stroke: {color_hex}')
        
        # In SVG stylesheets
        content = content.replace('fill:black', f'fill:{color_hex}')
        content = content.replace('stroke:black', f'stroke:{color_hex}')
        
        # Inject style rule for standard SVG elements in matplotlib output (#text_1 group)
        style_rule = f"\n  #text_1 {{ fill: {color_hex}; stroke: {color_hex}; }}\n"
        content = content.replace('</style>', f'{style_rule}</style>')
        
        with open(svg_path, 'w', encoding='utf-8') as f:
            f.write(content)
    except Exception as e:
        sys.stderr.write(f"Warning: Failed to recolor SVG {svg_path}: {e}\n")

def read_svg_dimensions(svg_path, scale_factor):
    """
    Reads the width and height viewport dimensions from an SVG file,
    divides them by the scale_factor to get the original logical dimensions,
    and returns them as a tuple of rounded integers (w_px, h_px).
    """
    try:
        with open(svg_path, 'r', encoding='utf-8') as f:
            content = f.read()
        width_match = re.search(r'width="([0-9.]+)(?:px|pt)?"', content)
        height_match = re.search(r'height="([0-9.]+)(?:px|pt)?"', content)
        if width_match and height_match:
            w_svg = float(width_match.group(1))
            h_svg = float(height_match.group(1))
            return int(round(w_svg / scale_factor)), int(round(h_svg / scale_factor))
    except Exception as e:
        sys.stderr.write(f"Warning: Failed to read SVG dimensions: {e}\n")
    return None, None

def make_svg_dimensions_integer(svg_path, scale_factor):
    """
    Rewrites the SVG's width and height viewport dimensions from fractional points
    to rounded integer pixels multiplied by scale_factor, preventing sub-pixel scaling interpolation.
    Returns (w_px, h_px) representing the original logical pixel dimensions.
    """
    w_px, h_px = 0, 0
    try:
        with open(svg_path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        # Find width and height in pt
        width_match = re.search(r'width="([0-9.]+)pt"', content)
        height_match = re.search(r'height="([0-9.]+)pt"', content)
        if width_match and height_match:
            w_pt = float(width_match.group(1))
            h_pt = float(height_match.group(1))
            # Convert pt to pixels (1pt = 1.33333px) and round to integer
            w_px = int(round(w_pt * 1.33333))
            h_px = int(round(h_pt * 1.33333))
            
            # Scale up to high resolution for high DPI displays
            w_svg = w_px * scale_factor
            h_svg = h_px * scale_factor
            
            # Replace in the SVG content
            content = re.sub(r'width="[0-9.]+pt"', f'width="{w_svg}px"', content, count=1)
            content = re.sub(r'height="[0-9.]+pt"', f'height="{h_svg}px"', content, count=1)
            
            with open(svg_path, 'w', encoding='utf-8') as f:
                f.write(content)
    except Exception as e:
        sys.stderr.write(f"Warning: Failed to make SVG dimensions integer: {e}\n")
    return w_px, h_px

def get_formula_hash(formula, color_hex, is_block, font_size):
    # Compute unique hash for a formula, its color, layout style (inline vs block), and font size
    hasher = hashlib.sha256()
    hasher.update(formula.encode('utf-8'))
    hasher.update((color_hex or "").encode('utf-8'))
    hasher.update(str(is_block).encode('utf-8'))
    hasher.update(str(font_size).encode('utf-8'))
    return hasher.hexdigest()[:16]

def render_formula(formula, color_hex, cache_dir, is_block, font_size):
    """
    Renders a single LaTeX formula to an SVG file.
    Returns a tuple of (file_url_or_fallback, w_px, h_px).
    """
    clean_formula = formula.strip()
    
    # Normalize for MathTextParser (needs to start/end with a single $)
    # Strip existing delimiters if present
    if clean_formula.startswith('$$') and clean_formula.endswith('$$'):
        math_content = clean_formula[2:-2]
    elif clean_formula.startswith(r'\[') and clean_formula.endswith(r'\]'):
        math_content = clean_formula[2:-2]
    elif clean_formula.startswith(r'\(') and clean_formula.endswith(r'\)'):
        math_content = clean_formula[2:-2]
    elif clean_formula.startswith('$') and clean_formula.endswith('$'):
        math_content = clean_formula[1:-1]
    else:
        math_content = clean_formula

    math_content = math_content.strip()
    latex_str = f"${math_content}$"
    
    # Hash for caching
    f_hash = get_formula_hash(latex_str, color_hex, is_block, font_size)
    SCALE_FACTOR = 4
    # Include scale factor in filename to automatically invalidate older low-res cache files
    filename = f"latex_{f_hash}_s{SCALE_FACTOR}.svg"
    filepath = os.path.join(cache_dir, filename)
    
    if os.path.exists(filepath):
        w_px, h_px = read_svg_dimensions(filepath, SCALE_FACTOR)
        if w_px is not None and h_px is not None:
            return f"file://{filepath}", w_px, h_px
        
    try:
        fig = Figure(figsize=(0.1, 0.1))
        FigureCanvasAgg(fig)
        # Size block math equations at double size (2x), and match inline formulas exactly to font_size
        fontsize = font_size * 2 if is_block else font_size
        fig.text(0, 0, latex_str, fontsize=fontsize, ha='left', va='baseline')
        fig.savefig(filepath, format='svg', bbox_inches='tight', transparent=True, pad_inches=0.02)
        recolor_svg(filepath, color_hex)
        w_px, h_px = make_svg_dimensions_integer(filepath, SCALE_FACTOR)
        return f"file://{filepath}", w_px, h_px
    except Exception as e:
        sys.stderr.write(f"Error rendering formula '{latex_str}': {e}\n")
        return fallback_replace_formula(math_content), None, None

def main():
    # Parse arguments
    color_hex = ""
    cache_dir = os.path.expanduser("~/.cache/plasmallm/latex")
    font_size = 11  # Default fallback font size
    
    args = sys.argv[1:]
    for i in range(len(args)):
        if args[i] == "--color" and i + 1 < len(args):
            color_hex = args[i+1]
        elif args[i] == "--cache-dir" and i + 1 < len(args):
            cache_dir = args[i+1]
        elif args[i] == "--font-size" and i + 1 < len(args):
            try:
                font_size = int(args[i+1])
            except ValueError:
                pass
            
    # Ensure cache directory exists
    os.makedirs(cache_dir, exist_ok=True)
    
    # Read text from stdin
    text = sys.stdin.read()
    
    # Temporarily hide escaped dollars
    text = text.replace(r'\$', '__ESCAPED_DOLLAR__')
    
    # Regex to match LaTeX math delimiters:
    # 1. $$ ... $$
    # 2. \[ ... \]
    # 3. \( ... \)
    # 4. $ ... $
    math_pattern = re.compile(
        r'(\$\$(.*?)\$\$)|'
        r'(\\\[(.*?)\\\])|'
        r'(\\\((.*?)\\\))|'
        r'((?<!\\)\$([^\s\$](?:[^\$]*?[^\s\$])?)(?<!\\)\$)',
        re.DOTALL
    )
    
    pos = 0
    result = []
    
    for match in math_pattern.finditer(text):
        # Add preceding plaintext segment
        result.append(text[pos:match.start()])
        
        formula = match.group(0)
        is_block = formula.startswith('$$') or formula.startswith(r'\[')
        
        res, w_px, h_px = render_formula(formula, color_hex, cache_dir, is_block, font_size)
        
        if res.startswith("file://"):
            if w_px and h_px:
                # Use HTML img tag with alignment and width/height attributes for high-DPI scaling and vertical alignment
                if is_block:
                    replacement = f'<br /><div align="center" style="margin-top: 10px; margin-bottom: 10px;"><a href="{res}"><img src="{res}" width="{w_px}" height="{h_px}" /></a></div><br />'
                else:
                    replacement = f' <img src="{res}" width="{w_px}" height="{h_px}" align="middle" /> '
            else:
                alt_text = formula.replace('$', '').replace('\\', '').replace('"', '').replace('\n', ' ')
                if is_block:
                    replacement = f'\n\n![{alt_text}]({res})\n\n'
                else:
                    replacement = f' ![{alt_text}]({res}) '
        else:
            replacement = f'\n\n{res}\n\n' if is_block else f' {res} '
            
        result.append(replacement)
        pos = match.end()
        
    result.append(text[pos:])
    
    # Reassemble and restore escaped dollars
    final_text = "".join(result).replace('__ESCAPED_DOLLAR__', '$')
    sys.stdout.write(final_text)

if __name__ == '__main__':
    main()
