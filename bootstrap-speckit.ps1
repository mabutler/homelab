[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$TargetRepo,
    [switch]$Force,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

if ($Help) {
    Write-Host "Usage: pwsh ./bootstrap-speckit.ps1 <target-repo> [-Force] [-Help]"
    exit 0
}

if ([string]::IsNullOrWhiteSpace($TargetRepo)) {
    [Console]::Error.WriteLine("ERROR: Target repository path is required. Run with -Help for usage.")
    exit 1
}

$SrcRoot = $PSScriptRoot
if (-not $SrcRoot) { $SrcRoot = (Get-Location).Path }

if ((Test-Path -LiteralPath $TargetRepo -PathType Leaf)) {
    [Console]::Error.WriteLine("ERROR: Target path exists and is a file, not a directory: $TargetRepo")
    exit 1
}

if (-not (Test-Path -LiteralPath $TargetRepo -PathType Container)) {
    try {
        New-Item -ItemType Directory -Path $TargetRepo -Force | Out-Null
    } catch {
        [Console]::Error.WriteLine("ERROR: Target directory is not writable: $TargetRepo")
        exit 1
    }
}

$TargetDir = (Resolve-Path -LiteralPath $TargetRepo).Path
$ResolvedSrc = (Resolve-Path -LiteralPath $SrcRoot).Path

if ($ResolvedSrc -eq $TargetDir) {
    [Console]::Error.WriteLine("ERROR: Target repository cannot be the source toolkit repository itself.")
    exit 1
}

$RequiredAssets = @(
    ".specify/templates/spec-template.md",
    ".specify/templates/plan-template.md",
    ".specify/templates/tasks-template.md",
    ".specify/templates/checklist-template.md",
    ".specify/templates/constitution-template.md",
    ".specify/templates/coding-standards-template.md",
    ".specify/templates/logging-standards-template.md",
    ".specify/templates/roadmap-template.md",
    ".specify/extensions.yml",
    ".agents/agents/speckit-reasoner.md",
    ".agents/agents/speckit-executor.md"
)

foreach ($req in $RequiredAssets) {
    $fullReq = Join-Path $ResolvedSrc $req
    if (-not (Test-Path -LiteralPath $fullReq -PathType Leaf)) {
        [Console]::Error.WriteLine("CRITICAL: Source bundle is missing required assets: $req")
        exit 1
    }
}

$ModeDesc = if ($Force) { "Force (overwriting managed files)" } else { "Normal (skipping existing managed files)" }

Write-Host "=== Spec Kit Bootstrapper Seeder ==="
Write-Host "Target Repository: $TargetDir"
Write-Host "Mode: $ModeDesc`n"

$Copied = 0
$Skipped = 0
$SpecifyCount = 0
$AgentsCount = 0

# Protected User-State Boundary (PRESERVE_USER_STATE):
# Never clobbers .specify/memory/*, overrides, feature.json, local profiles, specs/*, or root ROADMAP.md
$SourceFiles = Get-ChildItem -Path (Join-Path $ResolvedSrc ".specify"), (Join-Path $ResolvedSrc ".agents") -Recurse -File | Where-Object {
    $rel = $_.FullName.Substring($ResolvedSrc.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar).Replace('\', '/')
    -not ($rel.StartsWith(".specify/memory/") -or $rel.StartsWith(".specify/templates/overrides/") -or $rel -eq ".specify/feature.json" -or ($rel.StartsWith(".agents/agents/") -and $rel.EndsWith(".local.md")))
}

foreach ($file in $SourceFiles) {
    $relPath = $file.FullName.Substring($ResolvedSrc.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $destPath = Join-Path $TargetDir $relPath
    $destDir = [System.IO.Path]::GetDirectoryName($destPath)
    if (-not (Test-Path -LiteralPath $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    if ((Test-Path -LiteralPath $destPath) -and -not $Force) {
        $Skipped++
    } else {
        Copy-Item -LiteralPath $file.FullName -Destination $destPath -Force
        $Copied++
        $relNorm = $relPath.Replace('\', '/')
        if ($relNorm.StartsWith(".specify/")) { $SpecifyCount++ }
        elseif ($relNorm.StartsWith(".agents/")) { $AgentsCount++ }
    }
}

$GitIgnore = Join-Path $TargetDir ".gitignore"
$Pattern = ".agents/agents/*.local.md"
if (-not (Test-Path -LiteralPath $GitIgnore)) {
    Set-Content -LiteralPath $GitIgnore -Value $Pattern
    Write-Host "[INFO] Created .gitignore with $Pattern"
} else {
    $content = Get-Content -LiteralPath $GitIgnore -Raw
    if ($content -notmatch [regex]::Escape($Pattern)) {
        Add-Content -LiteralPath $GitIgnore -Value "`n# Spec Kit local agent profiles`n$Pattern"
        Write-Host "[INFO] Updated .gitignore with $Pattern"
    } else {
        Write-Host "[INFO] Verified .gitignore contains $Pattern"
    }
}

Write-Host "[INFO] Verified source bundle integrity"
Write-Host "[INFO] Seeded .specify/ configuration and templates ($SpecifyCount files)"
Write-Host "[INFO] Seeded .agents/ skills and agent definitions ($AgentsCount files)`n"

Write-Host "Files Copied: $Copied"
Write-Host "Files Skipped: $Skipped (existing)`n"
Write-Host "Next Steps:"
Write-Host "1. Open your AI agent in the target repository"
Write-Host "2. Run /speckit-bootstrap to verify configuration and manifests"
Write-Host "3. Run /speckit-constitution to ratify project governance standards"
Write-Host "===================================="
