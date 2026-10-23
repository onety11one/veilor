[CmdletBinding()]
param(
    [string]$AppRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$AppRoot = [IO.Path]::GetFullPath($AppRoot)
$dependencyWorkspace = Split-Path $AppRoot -Parent
$sourceLock = Get-Content -LiteralPath (Join-Path $AppRoot 'veilor/upstream-sources.lock.json') -Raw | ConvertFrom-Json

function Invoke-DependencyGit {
    param([string]$Directory, [string[]]$GitArguments)
    $gitOutput = & git -C $Directory @GitArguments
    if ($LASTEXITCODE -ne 0) { throw "git failed in $Directory (exit $LASTEXITCODE)" }
    return ($gitOutput -join "`n").Trim()
}

foreach ($dependency in $sourceLock.dependencies) {
    if ($dependency.directory -notin @('libXray', 'Vole') -or $dependency.commit -notmatch '^[0-9a-f]{40}$') {
        throw 'Unsupported dependency name or commit in source manifest'
    }
    $dependencyPath = Join-Path $dependencyWorkspace $dependency.directory
    if (Test-Path -LiteralPath $dependencyPath) {
        if (-not (Test-Path -LiteralPath (Join-Path $dependencyPath '.git'))) {
            throw "Existing directory is not a Git checkout: $dependencyPath"
        }
        $actualRoot = Invoke-DependencyGit $dependencyPath @('rev-parse', '--show-toplevel')
        if ([IO.Path]::GetFullPath($actualRoot) -ne [IO.Path]::GetFullPath($dependencyPath)) {
            throw "Unexpected Git root at $dependencyPath"
        }
        $actualCommit = Invoke-DependencyGit $dependencyPath @('rev-parse', 'HEAD')
        $actualRemote = Invoke-DependencyGit $dependencyPath @('remote', 'get-url', 'origin')
        $dirty = Invoke-DependencyGit $dependencyPath @('status', '--porcelain')
        if ($actualCommit -ne $dependency.commit -or $actualRemote.TrimEnd('/') -ne $dependency.repository -or $dirty) {
            throw "Existing $($dependency.directory) differs from the manifest or has changes; nothing was reset"
        }
    } else {
        if ($CheckOnly) { throw "Missing dependency: $dependencyPath" }
        New-Item -ItemType Directory -Path $dependencyPath | Out-Null
        Invoke-DependencyGit $dependencyPath @('init') | Out-Host
        Invoke-DependencyGit $dependencyPath @('config', 'core.longpaths', 'true') | Out-Host
        Invoke-DependencyGit $dependencyPath @('remote', 'add', 'origin', [string]$dependency.repository) | Out-Host
        Invoke-DependencyGit $dependencyPath @('remote', 'set-url', '--push', 'origin', 'DISABLED') | Out-Host
        Invoke-DependencyGit $dependencyPath @('fetch', '--depth', '1', '--no-tags', 'origin', [string]$dependency.commit) | Out-Host
        Invoke-DependencyGit $dependencyPath @('checkout', '--detach', [string]$dependency.commit) | Out-Host
    }
    Write-Host "$($dependency.directory): $($dependency.commit)"
}
