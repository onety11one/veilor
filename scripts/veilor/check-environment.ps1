param(
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$baseline = '1f52c28e062fe55d7c3ccc254f1a90d53fd8c103'
$blockers = [System.Collections.Generic.List[string]]::new()

function Invoke-RepoGit {
    param([string[]]$Arguments)
    $result = @(& git -C $repoRoot @Arguments)
    if ($LASTEXITCODE -ne 0) { throw "Git failed: $($Arguments -join ' ')" }
    return $result
}

$headSha = (Invoke-RepoGit -Arguments @('rev-parse', 'HEAD')) -join ''
$branchName = (Invoke-RepoGit -Arguments @('branch', '--show-current')) -join ''
$null = Invoke-RepoGit -Arguments @('cat-file', '-e', "$baseline`^{commit}")
$baselineDifferences = @(Invoke-RepoGit -Arguments @('diff', '--name-only', $baseline, '--'))
$runtimeDifferences = @($baselineDifferences | Where-Object {
    $_ -notmatch '^(docs/veilor/|scripts/veilor/|test/veilor/)'
})
$untracked = @(Invoke-RepoGit -Arguments @('ls-files', '--others', '--exclude-standard'))

$toolPaths = [ordered]@{}
foreach ($toolName in @('flutter', 'dart', 'cmake')) {
    $command = Get-Command $toolName -ErrorAction SilentlyContinue
    $toolPaths[$toolName] = if ($command) { $command.Source } else { $null }
    if (-not $command) { $blockers.Add("Missing command on PATH: $toolName") }
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$visualStudio = $null
if (Test-Path -LiteralPath $vswhere) {
    $visualStudio = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath) -join ''
    if ($LASTEXITCODE -ne 0) { throw 'Visual Studio discovery failed.' }
}
if (-not $visualStudio) { $blockers.Add('Missing Visual Studio installation with C++ x64/x86 tools.') }

$pubspec = Get-Content -LiteralPath (Join-Path $repoRoot 'pubspec.yaml') -Raw
$pluginMatch = [regex]::Match($pubspec, '(?m)^  vpn_service:\s*\r?\n\s+path:\s*([^\r\n#]+)')
if (-not $pluginMatch.Success) { throw 'Expected local vpn_service override was not found. Review dependency configuration.' }
$pluginRelativePath = $pluginMatch.Groups[1].Value.Trim()
$pluginPath = [IO.Path]::GetFullPath((Join-Path $repoRoot $pluginRelativePath))
$pluginPresent = Test-Path -LiteralPath (Join-Path $pluginPath 'pubspec.yaml')
if (-not $pluginPresent) { $blockers.Add("Missing local vpn_service package: $pluginPath") }

$missingImports = [System.Collections.Generic.HashSet[string]]::new()
$importPattern = '(?:import|export)\s+[''"]package:karing/([^''"]+)[''"]'
Get-ChildItem -LiteralPath (Join-Path $repoRoot 'lib') -Filter '*.dart' -Recurse | ForEach-Object {
    $content = Get-Content -LiteralPath $_.FullName -Raw
    foreach ($importMatch in [regex]::Matches($content, $importPattern)) {
        $relativeImport = $importMatch.Groups[1].Value
        if (-not (Test-Path -LiteralPath (Join-Path (Join-Path $repoRoot 'lib') $relativeImport))) {
            $null = $missingImports.Add($relativeImport)
        }
    }
}
if ($missingImports.Count -gt 0) { $blockers.Add("Missing internal Dart import targets: $($missingImports.Count)") }
$nativeCorePath = Join-Path $repoRoot 'bind/windows/core'
$nativeCorePresent = Test-Path -LiteralPath $nativeCorePath
if (-not $nativeCorePresent) { $blockers.Add('Missing native Windows core directory: bind/windows/core') }

$report = [ordered]@{
    baseline = $baseline
    head = $headSha
    branch = $branchName
    repository = $repoRoot
    origin = (Invoke-RepoGit -Arguments @('remote', 'get-url', 'origin')) -join ''
    originalRuntimeFilesUnchanged = ($runtimeDifferences.Count -eq 0)
    changedTrackedFiles = $baselineDifferences
    untrackedFiles = $untracked
    toolPaths = $toolPaths
    visualStudioCpp = $visualStudio
    vpnServicePath = $pluginPath
    vpnServicePresent = $pluginPresent
    missingInternalDartImports = @($missingImports | Sort-Object)
    nativeWindowsCorePresent = $nativeCorePresent
    buildPrerequisitesDetected = ($blockers.Count -eq 0)
    blockers = @($blockers)
    scope = 'Discovery only. Does not validate SDK versions, Windows SDK, packages, native core binaries, compilation or runtime parity. Run flutter doctor -v and baseline build after resolving blockers.'
}

$json = $report | ConvertTo-Json -Depth 5
if ($ReportPath) {
    $absoluteReportPath = [IO.Path]::GetFullPath($ReportPath)
    $parentPath = Split-Path -Parent $absoluteReportPath
    if (-not (Test-Path -LiteralPath $parentPath)) { throw "Report directory does not exist: $parentPath" }
    [IO.File]::WriteAllText($absoluteReportPath, $json, [Text.UTF8Encoding]::new($false))
}
$json
if ($blockers.Count -gt 0) { exit 1 }
