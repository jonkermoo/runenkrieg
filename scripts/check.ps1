# The four gates. Nothing reaches Studio unless all four pass.
$ErrorActionPreference = "Stop"
Set-Location (Split-Path $PSScriptRoot -Parent)
$failed = @()
# selene's Roblox std is generated, not in git
if (-not (Test-Path roblox.yml)) { selene generate-roblox-std | Out-Null }

Write-Host "== 1/4 rojo build" -ForegroundColor Cyan
New-Item -ItemType Directory -Force build | Out-Null
rojo build default.project.json -o build/runenkrieg.rbxl; if ($LASTEXITCODE) { $failed += "rojo" }

Write-Host "== 2/4 tests (lune)" -ForegroundColor Cyan
lune run tests/run.luau; if ($LASTEXITCODE) { $failed += "tests" }

Write-Host "== 3/4 lint (selene)" -ForegroundColor Cyan
selene src; if ($LASTEXITCODE) { $failed += "selene" }

Write-Host "== 4/4 format (stylua --check)" -ForegroundColor Cyan
StyLua --check src tests; if ($LASTEXITCODE) { $failed += "stylua" }

if ($failed.Count) { Write-Host "FAILED: $($failed -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host "ALL 4 CHECKS PASSED" -ForegroundColor Green
