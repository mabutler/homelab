<#
.SYNOPSIS
    Workstation disaster recovery orchestrator for fidelacchius.
.DESCRIPTION
    Extracts Backblaze B2 and Restic bootstrap credentials from local inventory
    if not explicitly passed, connects to the target Linux host over SSH, and executes
    scripts/restore-from-b2.sh to restore secrets and application datasets.
.PARAMETER HostAddress
    Target IP address or hostname (default: 192.168.4.57).
.PARAMETER User
    Remote administrative SSH username (default: admin).
.PARAMETER IdentityFile
    Path to private SSH key for authentication.
.PARAMETER AccountId
    Backblaze B2 Application Key ID.
.PARAMETER AccountKey
    Backblaze B2 Application Key.
.PARAMETER Repository
    Restic repository URI (e.g. b2:fidelacchius-backups:fidelacchius).
.PARAMETER Password
    Restic client-side encryption password.
.PARAMETER Snapshot
    Snapshot ID to restore (default: latest).
.PARAMETER TargetDir
    Target extraction directory on target host (default: /).
.PARAMETER IncludePath
    Subpath to selectively restore (e.g. etc/homelab/vault.yml).
.PARAMETER Force
    Allow overwriting non-empty target directory.
.PARAMETER DryRun
    Simulate restore and list files without modifying filesystem.
#>
[CmdletBinding()]
param(
    [string]$HostAddress = "192.168.4.57",
    [string]$User = "admin",
    [string]$IdentityFile = "",
    [string]$AccountId = "",
    [string]$AccountKey = "",
    [string]$Repository = "",
    [string]$Password = "",
    [string]$Snapshot = "latest",
    [string]$TargetDir = "/",
    [string]$IncludePath = "",
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$VaultFile = Join-Path $RepoRoot "ansible\inventory\group_vars\all\vault.yml"

# Auto-extract credentials from vault.yml if not provided
if ((-not $AccountId -or -not $AccountKey -or -not $Repository -or -not $Password) -and (Test-Path $VaultFile)) {
    Write-Host "Extracting backup credentials from $VaultFile..." -ForegroundColor Cyan
    $content = Get-Content -Raw $VaultFile
    if (-not $AccountId -and $content -match '(?m)^vault_b2_account_id:\s*["'']?([^"''\r\n]+)["'']?') {
        $AccountId = $matches[1].Trim()
    }
    if (-not $AccountKey -and $content -match '(?m)^vault_b2_account_key:\s*["'']?([^"''\r\n]+)["'']?') {
        $AccountKey = $matches[1].Trim()
    }
    if (-not $Repository -and $content -match '(?m)^vault_restic_repository:\s*["'']?([^"''\r\n]+)["'']?') {
        $Repository = $matches[1].Trim()
    }
    if (-not $Password -and $content -match '(?m)^vault_restic_password:\s*["'']?([^"''\r\n]+)["'']?') {
        $Password = $matches[1].Trim()
    }
}

if (-not $AccountId -or -not $AccountKey -or -not $Repository -or -not $Password) {
    Write-Error "Missing required backup credentials. Provide via parameters or ensure ansible/inventory/group_vars/all/vault.yml exists."
    exit 1
}

$sshOpts = @("-n", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=30")
$scpOpts = @("-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=30")
if ($IdentityFile) {
    $sshOpts += @("-i", $IdentityFile)
    $scpOpts += @("-i", $IdentityFile)
}

Write-Host "=== fidelacchius Disaster Recovery Orchestrator ===" -ForegroundColor Cyan
Write-Host "Target Host : $User@$HostAddress"
Write-Host "Snapshot    : $Snapshot"
Write-Host "Target Dir  : $TargetDir"
if ($IncludePath) { Write-Host "Include     : $IncludePath" }
if ($Force) { Write-Host "Force       : Enabled (Overwrite allowed)" -ForegroundColor Yellow }
if ($DryRun) { Write-Host "Mode        : Dry-Run" -ForegroundColor Yellow }

# 1. Test SSH connectivity
Write-Host "Testing SSH connection to $User@$HostAddress..."
$testResult = & ssh @sshOpts "$User@$HostAddress" "uname -s" 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to connect to $User@$HostAddress over SSH: $testResult"
    exit 4
}

# 2. Upload restore script to remote host
$localScript = Join-Path $RepoRoot "scripts\restore-from-b2.sh"
Write-Host "Uploading restore-from-b2.sh to /tmp/restore-from-b2.sh..."
& scp.exe @scpOpts "$localScript" "${User}@${HostAddress}:/tmp/restore-from-b2.sh"
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to scp restore-from-b2.sh to remote host."
    exit 2
}

# 3. Construct remote execution command
$flags = @()
$flags += "--snapshot '$Snapshot'"
$flags += "--target-dir '$TargetDir'"
if ($IncludePath) { $flags += "--include-path '$IncludePath'" }
if ($Force) { $flags += "--force" }
if ($DryRun) { $flags += "--dry-run" }

$flagString = $flags -join " "
$remoteCommand = "chmod +x /tmp/restore-from-b2.sh && sudo B2_ACCOUNT_ID='$AccountId' B2_ACCOUNT_KEY='$AccountKey' RESTIC_REPOSITORY='$Repository' RESTIC_PASSWORD='$Password' /tmp/restore-from-b2.sh $flagString"

Write-Host "Executing disaster recovery restoration on target host..." -ForegroundColor Green
& ssh.exe @sshOpts "$User@$HostAddress" $remoteCommand
$exitCode = $LASTEXITCODE

# 4. Clean up remote script
& ssh.exe @sshOpts "$User@$HostAddress" "rm -f /tmp/restore-from-b2.sh"

if ($exitCode -eq 0) {
    Write-Host "Disaster recovery operation completed successfully." -ForegroundColor Green
} else {
    Write-Error "Disaster recovery failed with exit code $exitCode."
}

exit $exitCode
