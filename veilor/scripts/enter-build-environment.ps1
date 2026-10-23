# Dot-source this optional helper for the isolated SDK layout used in the audit.
# It changes only the current process environment; it does not install tools.
[CmdletBinding()]
param(
    [string]$WorkRoot = (Split-Path (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path -Parent),
    [string]$ToolsRoot,
    [string]$CargoHome
)

$ErrorActionPreference = 'Stop'
if (-not $ToolsRoot) { $ToolsRoot = Join-Path $WorkRoot 'toolchains' }
if (-not $CargoHome) { $CargoHome = Join-Path $ToolsRoot 'cargo' }
foreach ($requiredTool in @('flutter/bin/flutter.bat', 'go/bin/go.exe', 'python-deps/clang/native/libclang.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ToolsRoot $requiredTool))) { throw "Missing tool: $requiredTool" }
}
if (-not (Test-Path -LiteralPath (Join-Path $CargoHome 'bin/cargo.exe'))) { throw 'CargoHome must point to the installed Cargo directory' }
$env:RUSTUP_HOME = Join-Path $ToolsRoot 'rustup'
$env:CARGO_HOME = $CargoHome
$env:GOPATH = Join-Path $WorkRoot 'go-work'
$env:GOCACHE = Join-Path $WorkRoot 'go-cache'
$env:PUB_CACHE = Join-Path $WorkRoot 'pub-cache'
$env:APPDATA = Join-Path $WorkRoot 'references/flutter-appdata'
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
$env:CI = 'true'
$env:CARGO_NET_GIT_FETCH_WITH_CLI = 'true'
$env:LIBCLANG_PATH = Join-Path $ToolsRoot 'python-deps/clang/native'
$env:PATH = (Join-Path $ToolsRoot 'flutter/bin') + ';' + (Join-Path $ToolsRoot 'go/bin') + ';' + (Join-Path $CargoHome 'bin') + ';' + $env:PATH
$mingwToolchain = Get-ChildItem -LiteralPath $ToolsRoot -Directory -Filter 'llvm-mingw-*' | Select-Object -First 1
if ($mingwToolchain) { $env:PATH = (Join-Path $mingwToolchain.FullName 'bin') + ';' + $env:PATH }
$gitPerlDirectory = 'C:/Program Files/Git/usr/bin'
if (Test-Path "$gitPerlDirectory/perl.exe") { $env:PATH += ";$gitPerlDirectory" }
