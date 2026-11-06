#!/usr/bin/env python3
"""Lists the localization keys used by the app, as SwiftUI/Foundation will look them up.

Keys are the Italian source strings. Interpolations become format specifiers:
Int expressions -> %lld, Int32 (exit codes) -> %d, everything else -> %@.
A literal % becomes %% in keys built from interpolated literals.

Usage: scripts/extract-strings.py            -> prints keys
       scripts/extract-strings.py --check F  -> exit 1 if F (a .strings file) lacks keys or has extra ones
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = sorted((ROOT / "Sources" / "ClaudeLauncher").glob("*.swift")) + [
    ROOT / "Sources/LauncherCore" / n for n in ("LauncherBuilder.swift", "CodeEnvironments.swift", "Shell.swift", "Model.swift", "Badge.swift")]

# Calls whose first string-literal argument is a LocalizedStringKey / LocalizationValue.
CALLS = r'(?:Text|Button|Label|Section|LabeledContent|TextField|Toggle|Picker|Menu|Link|Window|ContentUnavailableView|\.help|\.navigationTitle|\.confirmationDialog|String\(localized:|LocalizedStringKey|prompt: Text)'
LIT = r'"((?:[^"\\]|\\.)*)"'

def literal_to_key(lit):
    out, i, has_interp = "", 0, False
    while i < len(lit):
        if lit.startswith("\\(", i):
            depth, j = 1, i + 2
            while depth:
                depth += {"(": 1, ")": -1}.get(lit[j], 0); j += 1
            expr = lit[i + 2:j - 1]
            has_interp = True
            out += "%lld" if expr.startswith("Int(") else "%d" if expr == "status" else "%@"
            i = j
        elif lit.startswith('\\"', i): out += '"'; i += 2
        elif lit.startswith("\\n", i): out += "\n"; i += 2
        else: out += lit[i]; i += 1
    if has_interp:
        # literal % (not a specifier we inserted) must be doubled
        out = re.sub(r'%(?!(?:lld|d|@))', '%%', out)
    return out

def scan_literals(line):
    """Yields (start, body) for each top-level Swift string literal on a line,
    handling nested interpolations like "\\(x ? "a" : "b")"."""
    i = 0
    while i < len(line):
        if line.startswith("//", i): return
        if line[i] == '"' and not line.startswith('"""', i):
            j, depth = i + 1, 0
            while j < len(line):
                c = line[j]
                if depth == 0 and c == "\\" and j + 1 < len(line) and line[j + 1] != "(":
                    j += 2; continue
                if c == "\\" and line.startswith("\\(", j):
                    depth += 1; j += 2; continue
                if depth and c == "(":
                    depth += 1
                elif depth and c == ")":
                    depth -= 1
                elif depth and c == '"':
                    k = j + 1  # skip nested literal
                    while k < len(line) and line[k] != '"':
                        k += 2 if line[k] == "\\" else 1
                    j = k
                elif depth == 0 and c == '"':
                    break
                j += 1
            yield i, line[i + 1:j]
            i = j + 1
        else:
            i += 1

def keys():
    found = {}
    for path in SOURCES:
        carry = False  # a localizable call continued on the next line (ternaries, long args)
        for lineno, line in enumerate(path.read_text().splitlines(), 1):
            if line.strip().startswith("//"): continue
            hit = re.search(CALLS, line) or "failure:" in line or "Preset(name:" in line
            if not hit and not carry: carry = False; continue
            carry = bool(hit) and line.rstrip().endswith((":", "?", "(", ","))
            for start, lit in scan_literals(line):
                before = line[:start]
                if re.search(r'(systemName|systemImage|id|named|forType|selection|text|separator|with|of): *$', before): continue
                if re.search(r'(appendingPathComponent|URL\(string:|fileURLWithPath:)\s*$', before): continue
                explicit = before.rstrip().endswith("String(localized:")
                if not re.search(r'[A-Za-zÀ-ÿ]', lit): continue
                if not explicit and lit.startswith(("~", "/", "claude-", "%", "doc.", "check")): continue
                if lit in (": \\(detail)", "main", "Double Trouble", "trash", "terminal", "terminal.fill", "plus", "circle", "circle.fill"): continue
                found.setdefault(literal_to_key(lit), f"{path.name}:{lineno}")
    return found

def parse_strings(path):
    text = pathlib.Path(path).read_text()
    pairs = re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', text, re.M)
    unesc = lambda s: s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
    return {unesc(k): unesc(v) for k, v in pairs}

if __name__ == "__main__":
    k = keys()
    if len(sys.argv) > 2 and sys.argv[1] == "--check":
        have = parse_strings(sys.argv[2])
        missing = sorted(set(k) - set(have)); extra = sorted(set(have) - set(k))
        for x in missing: print("MANCA ", repr(x), k[x])
        for x in extra: print("IN PIÙ", repr(x))
        print(f"{len(k)} chiavi, {len(missing)} mancanti, {len(extra)} in più")
        sys.exit(1 if missing else 0)
    for key, where in sorted(k.items(), key=lambda kv: kv[1]):
        print(f"{where:28} {key!r}")
