<#
.SYNOPSIS
    Workstation verification runner for homelab2 Phase 5 Backup & Disaster Recovery.
.DESCRIPTION
    Uploads and executes the 8 automated backup acceptance assertions on the target host
    over SSH and outputs results in human-readable or JSON format.
.PARAMETER TargetHost
    Target IP address or hostname (default: 192.168.4.57).
.PARAMETER User
    Remote administrative SSH username (default: admin).
.PARAMETER IdentityFile
    Path to private SSH key for authentication.
.PARAMETER Json
    Output verification report in JSON format.
#>
[CmdletBinding()]
param(
    [string]$TargetHost = "192.168.4.57",
    [string]$User = "admin",
    [string]$IdentityFile = "",
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path

$sshOpts = @("-n", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=30")
$scpOpts = @("-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=30")
if ($IdentityFile) {
    $sshOpts += @("-i", $IdentityFile)
    $scpOpts += @("-i", $IdentityFile)
}

if (-not $Json) {
    Write-Host "=== fidelacchius Phase 5 Backup Acceptance Verification Runner ===" -ForegroundColor Cyan
    Write-Host "Target Host : $User@$TargetHost"
}

# 1. Test SSH connectivity
$testResult = & ssh @sshOpts "$User@$TargetHost" "uname -s" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to connect to $User@$TargetHost over SSH: $testResult"
    exit 4
}

# 2. Upload verification and restore scripts to remote host
$verifyScript = Join-Path $RepoRoot "scripts\verify-phase5-backup.sh"
$restoreScript = Join-Path $RepoRoot "scripts\restore-from-b2.sh"

& scp.exe @scpOpts "$verifyScript" "${User}@${TargetHost}:/tmp/verify-phase5-backup.sh"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to scp verify-phase5-backup.sh to remote host."
    exit 2
}

& scp.exe @scpOpts "$restoreScript" "${User}@${TargetHost}:/tmp/restore-from-b2.sh"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to scp restore-from-b2.sh to remote host."
    exit 2
}

# 3. Execute remote verification
$remoteArgs = ""
if ($Json) { $remoteArgs = "--json" }
$remoteCmd = "chmod +x /tmp/verify-phase5-backup.sh /tmp/restore-from-b2.sh && sudo /tmp/verify-phase5-backup.sh $remoteArgs"

& ssh.exe @sshOpts "$User@$TargetHost" $remoteCmd
$exitCode = $LASTEXITCODE

# 4. Clean up temporary scripts
& ssh.exe @sshOpts "$User@$TargetHost" "rm -f /tmp/verify-phase5-backup.sh /tmp/restore-from-b2.sh"

exit $exitCode
