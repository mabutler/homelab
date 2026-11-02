<#
.SYNOPSIS
    PowerShell acceptance verification runner for homelab2 Phase 4 (Storage Pooling & Data Resiliency Layer).
.DESCRIPTION
    Executes the 10-point acceptance assertion suite against the target production host
    via SSH or local execution.
.PARAMETER TargetHost
    Target IP address or hostname (default: 192.168.4.57).
.PARAMETER User
    Remote administrative SSH username (default: admin).
.PARAMETER IdentityFile
    Path to private SSH key for authentication.
#>
[CmdletBinding()]
param(
    [string]$TargetHost = "192.168.4.57",
    [string]$User = "admin",
    [string]$IdentityFile = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=== homelab2 Phase 4 Verification Orchestrator (PowerShell) ===" -ForegroundColor Cyan
Write-Host "Target Host : $User@$TargetHost"

$sshOpts = @("-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=30")
if ($IdentityFile) {
    $sshOpts += @("-i", $IdentityFile)
}

# Read verify script
$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$verifyScript = Join-Path $RepoRoot "scripts\verify-phase4.sh"

if (-not (Test-Path $verifyScript)) {
    Write-Error "Verification script not found at $verifyScript"
    exit 1
}

Write-Host "Executing verify-phase4.sh on remote target..." -ForegroundColor Yellow
$scriptContent = [System.IO.File]::ReadAllText($verifyScript)
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($scriptContent))

$remoteExecCmd = "echo '$b64' | base64 -d | bash -s -- --local"
& ssh @sshOpts "$User@$TargetHost" $remoteExecCmd
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host "`n[SUCCESS] Phase 4 Storage Pooling & Data Resiliency verification passed completely." -ForegroundColor Green
} else {
    Write-Host "`n[FAILED] Phase 4 verification failed with exit code $exitCode." -ForegroundColor Red
}

exit $exitCode
