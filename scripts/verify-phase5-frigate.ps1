<#
.SYNOPSIS
    PowerShell acceptance verification runner for homelab2 Phase 5 (Frigate NVR Application Deployment).
.DESCRIPTION
    Executes the 9-point acceptance assertion suite (FRG-01 to FRG-09) against the target production host
    via SSH or local execution.
.PARAMETER TargetHost
    Target IP address or hostname (default: 192.168.4.57).
.PARAMETER User
    Remote administrative SSH username (default: admin).
.PARAMETER IdentityFile
    Path to private SSH key for authentication.
.PARAMETER Json
    Switch to output results in JSON format.
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
    Write-Host "=== homelab2 Phase 5 Frigate NVR Verification Orchestrator (PowerShell) ===" -ForegroundColor Cyan
    Write-Host "Target Host : $User@$TargetHost"
}

$sshOpts = @("-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=30")
if ($IdentityFile) {
    $sshOpts += @("-i", $IdentityFile)
}

# Read verify script
$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$verifyScript = Join-Path $RepoRoot "scripts\verify-phase5-frigate.sh"

if (-not (Test-Path $verifyScript)) {
    Write-Error "Verification script not found at $verifyScript"
    exit 1
}

$scriptContent = [System.IO.File]::ReadAllText($verifyScript)
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($scriptContent))

$flags = "--local"
if ($Json) { $flags += " --json" }

$remoteExecCmd = "echo '$b64' | base64 -d | bash -s -- $flags"
& ssh @sshOpts "$User@$TargetHost" $remoteExecCmd
$exitCode = $LASTEXITCODE

if (-not $Json) {
    if ($exitCode -eq 0) {
        Write-Host "`n[SUCCESS] Phase 5 Frigate NVR verification passed completely." -ForegroundColor Green
    } else {
        Write-Host "`n[FAILED] Phase 5 Frigate NVR verification failed with exit code $exitCode." -ForegroundColor Red
    }
}

exit $exitCode
