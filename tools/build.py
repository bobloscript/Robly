#!/usr/bin/env python3
"""Bundle src/**/*.lua into a single loadstring-able file: dist/robly.lua.

Every module becomes a function in a table; `import("core/Theme")` loads it
once and caches the result. No external dependencies — just Python 3.

    python3 tools/build.py            # writes dist/robly.lua
    python3 tools/build.py --check    # fails if dist/robly.lua is outdated
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
DIST = ROOT / "dist" / "robly.lua"
VERSION = (ROOT / "VERSION").read_text().strip()

HEADER = """--[[
	Robly v{version} — UI library for Roblox scripts by RobScript
	https://robscript.com · https://github.com/bobloscript/Robly

	Built file. Edit the modules in src/ and run `python3 tools/build.py`.
	Public domain (The Unlicense).
]]
"""

PRELUDE = """local __modules = {}
local __cache = {}
local function import(name)
	local cached = __cache[name]
	if cached ~= nil then
		return cached
	end
	local loader = __modules[name]
	if not loader then
		error("[Robly] missing module: " .. tostring(name), 2)
	end
	local value = loader()
	__cache[name] = value
	return value
end
"""


def module_name(path: pathlib.Path) -> str:
    return path.relative_to(SRC).with_suffix("").as_posix()


def build() -> str:
    parts = [HEADER.format(version=VERSION), PRELUDE]
    files = sorted(SRC.rglob("*.lua"), key=lambda p: module_name(p))
    names = {module_name(p) for p in files}
    for path in files:
        name = module_name(path)
        source = path.read_text(encoding="utf-8")
        source = "\n".join(line for line in source.splitlines() if not line.startswith("--!"))
        for dep in re.findall(r'import\("([^"]+)"\)', source):
            if dep not in names:
                sys.exit(f"{path}: imports unknown module {dep!r}")
        source = source.replace("__VERSION__", VERSION)
        body = "\n".join(("\t" + line) if line.strip() else "" for line in source.splitlines())
        parts.append(f'__modules["{name}"] = function()\n{body}\nend\n')
    parts.append('return import("init")\n')
    return "\n".join(parts)


def main() -> None:
    output = build()
    if "--check" in sys.argv:
        current = DIST.read_text(encoding="utf-8") if DIST.exists() else ""
        if current != output:
            sys.exit("dist/robly.lua is out of date — run python3 tools/build.py")
        print("dist/robly.lua is up to date")
        return
    DIST.parent.mkdir(parents=True, exist_ok=True)
    DIST.write_text(output, encoding="utf-8")
    print(f"wrote {DIST.relative_to(ROOT)} ({len(output):,} bytes, {output.count(chr(10)):,} lines)")


if __name__ == "__main__":
    main()
