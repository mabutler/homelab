<#
.SYNOPSIS
    PowerShell 7+ acceptance verification runner for homelab2 Phase 5 Media & Arr Stack (Stage 1).
.DESCRIPTION
    Executes the 10-point acceptance assertion matrix (ARR-01 through ARR-10) locally or via SSH.
.PARAMETER TargetHost
    Target IP address or hostname (default: 192.168.4.57). Alias: Host, HostAddress.
.PARAMETER User
    Remote administrative SSH username (default: admin).
.PARAMETER IdentityFile
    Path to private SSH key for authentication. Alias: Identity.
.PARAMETER Local
    Execute verification locally without SSH.
.PARAMETER Json
    Output structured JSON report.
#>
[CmdletBinding()]
param(
    [Alias("Host", "HostAddress")]
    [string]$TargetHost = "192.168.4.57",
    [string]$User = "admin",
    [Alias("Identity")]
    [string]$IdentityFile = "",
    [switch]$Local,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$verifyScript = Join-Path $RepoRoot "scripts\verify-phase5-arr.sh"

if (-not (Test-Path $verifyScript)) {
    Write-Error "Verification script not found at $verifyScript"
    exit 1
}

$isVerbose = $PSBoundParameters.ContainsKey("Verbose")

if ($Local) {
    $argsList = @("--local")
    if ($Json) { $argsList += "--json" }
    if ($isVerbose) { $argsList += "--verbose" }
    & bash $verifyScript @argsList
    exit $LASTEXITCODE
}

if (-not $Json) {
    Write-Host "=== homelab2 Phase 5 Media & Arr Stage 1 Verification Orchestrator (PowerShell) ===" -ForegroundColor Cyan
    Write-Host "Target Host : $User@$TargetHost"
}

$sshOpts = @("-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=30")
if ($IdentityFile) {
    $sshOpts += @("-i", $IdentityFile)
}

$scriptContent = [System.IO.File]::ReadAllText($verifyScript)
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($scriptContent))

$flags = "--local"
if ($Json) { $flags += " --json" }
if ($isVerbose) { $flags += " --verbose" }

$remoteExecCmd = "echo '$b64' | base64 -d | bash -s -- $flags"
& ssh @sshOpts "$User@$TargetHost" $remoteExecCmd
$exitCode = $LASTEXITCODE

if (-not $Json) {
    if ($exitCode -eq 0) {
        Write-Host "`n[SUCCESS] Phase 5 Media & Arr Stage 1 verification passed completely." -ForegroundColor Green
    } else {
        Write-Host "`n[FAILED] Phase 5 Media & Arr Stage 1 verification failed with exit code $exitCode." -ForegroundColor Red
    }
}

exit $exitCode
