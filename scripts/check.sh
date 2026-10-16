#!/usr/bin/env bash
# The four gates (same as check.ps1). Nothing reaches Studio unless all four pass.
cd "$(dirname "$0")/.."
failed=()
# selene's Roblox std is generated, not in git
[ -f roblox.yml ] || selene generate-roblox-std >/dev/null

echo "== 1/4 rojo build"
mkdir -p build
rojo build default.project.json -o build/runenkrieg.rbxl || failed+=(rojo)

echo "== 2/4 tests (lune)"
lune run tests/run.luau || failed+=(tests)

echo "== 3/4 lint (selene)"
selene src || failed+=(selene)

echo "== 4/4 format (stylua --check)"
StyLua --check src tests || failed+=(stylua)

if [ ${#failed[@]} -gt 0 ]; then echo "FAILED: ${failed[*]}"; exit 1; fi
echo "ALL 4 CHECKS PASSED"
