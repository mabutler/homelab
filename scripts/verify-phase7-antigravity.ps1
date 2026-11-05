<#
.SYNOPSIS
    PowerShell acceptance verification runner for fidelacchius Feature 007 (Target Host Antigravity & Remote Control).
.DESCRIPTION
    Executes the 8-point acceptance assertion suite against the target production host
    via SSH or local execution.
.PARAMETER TargetHost
    Target IP address or hostname (default: 192.168.4.57).
.PARAMETER User
    Remote administrative SSH username (default: admin).
.PARAMETER IdentityFile
    Path to private SSH key for authentication.
.PARAMETER Json
    Emit output in structured JSON format.
#>
[CmdletBinding()]
param(
    [string]$TargetHost = "192.168.4.57",
    [string]$User = "admin",
    [string]$IdentityFile = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"

if (-not $Json) {
    Write-Host "=== fidelacchius Feature 007 Verification Orchestrator (PowerShell) ===" -ForegroundColor Cyan
    Write-Host "Target Host : $User@$TargetHost"
}

$sshOpts = @("-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=30")
if ($IdentityFile) {
    $sshOpts += @("-i", $IdentityFile)
}

# Read verify script
$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$verifyScript = Join-Path $RepoRoot "scripts\verify-phase7-antigravity.sh"

if (-not (Test-Path $verifyScript)) {
    Write-Error "Verification script not found at $verifyScript"
    exit 1
}

$scriptArgs = "--local"
if ($Json) {
    $scriptArgs += " --json"
} else {
    Write-Host "Executing verify-phase7-antigravity.sh on remote target..." -ForegroundColor Yellow
}

$scriptContent = [System.IO.File]::ReadAllText($verifyScript)
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($scriptContent))

$remoteExecCmd = "echo '$b64' | base64 -d | bash -s -- $scriptArgs"
& ssh @sshOpts "$User@$TargetHost" $remoteExecCmd
$exitCode = $LASTEXITCODE

if (-not $Json) {
    if ($exitCode -eq 0) {
        Write-Host "`n[SUCCESS] Feature 007 Antigravity Remote Control verification passed completely." -ForegroundColor Green
    } else {
        Write-Host "`n[FAILED] Feature 007 verification failed with exit code $exitCode." -ForegroundColor Red
    }
}

exit $exitCode
