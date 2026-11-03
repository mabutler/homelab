<#
.SYNOPSIS
    Cross-platform PowerShell runner for homelab2 Feature 007 (Target Host Antigravity & Remote Control).
.DESCRIPTION
    Orchestrates execution of Ansible playbooks against the production host.
    Supports native push if ansible-playbook is installed locally, or automated
    SSH sync & remote execution if running from a Windows operator workstation.
    Enforces explicit target readiness confirmation guard (FR-011).
.PARAMETER HostAddress
    Target IP address or hostname (default: 192.168.4.57).
.PARAMETER User
    Remote administrative SSH username (default: admin).
.PARAMETER IdentityFile
    Path to private SSH key for authentication.
.PARAMETER Playbook
    Ansible playbook to execute relative to ansible/ (default: playbooks/antigravity.yml).
.PARAMETER Tags
    Optional array of tags to filter execution.
.PARAMETER Check
    Perform a dry run / check mode (no changes committed).
.PARAMETER AgeKeyFile
    Path to operator SOPS age private key file.
.PARAMETER ConfirmTargetReady
    Mandatory safety guard confirmation flag per FR-011.
#>
[CmdletBinding()]
param(
    [string]$HostAddress = "192.168.4.57",
    [string]$User = "admin",
    [string]$IdentityFile = "",
    [string]$Playbook = "playbooks/antigravity.yml",
    [string[]]$Tags = @(),
    [switch]$Check,
    [string]$AgeKeyFile = "",
    [switch]$ConfirmTargetReady
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$AnsibleDir = Join-Path $RepoRoot "ansible"

# Enforce FR-011 safety confirmation guard
if (-not $ConfirmTargetReady) {
    Write-Host "`n[SAFETY GUARD ERROR] Missing mandatory confirmation flag: -ConfirmTargetReady" -ForegroundColor Red
    Write-Host "Per FR-011, automation MUST NOT execute against $User@$HostAddress until target readiness is explicitly confirmed." -ForegroundColor Yellow
    Write-Host "To proceed, run: ./scripts/apply-phase7-antigravity.ps1 -ConfirmTargetReady`n" -ForegroundColor Cyan
    exit 3
}

# Resolve age key file
if (-not $AgeKeyFile) {
    if ($env:SOPS_AGE_KEY_FILE) {
        $AgeKeyFile = $env:SOPS_AGE_KEY_FILE
    } else {
        $AgeKeyFile = Join-Path $env:USERPROFILE ".config\sops\age\keys.txt"
    }
}

Write-Host "=== homelab2 Feature 007 Convergence Orchestrator (PowerShell) ===" -ForegroundColor Cyan
Write-Host "Target Host : $User@$HostAddress"
Write-Host "Playbook    : $Playbook"
if ($Check) { Write-Host "Mode        : Check Mode (Dry Run)" -ForegroundColor Yellow }
if ($Tags.Count -gt 0) { Write-Host "Tags        : $($Tags -join ',')" }

$sshOpts = @("-n", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=30")
$scpOpts = @("-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=30")
if ($IdentityFile) {
    $sshOpts += @("-i", $IdentityFile)
    $scpOpts += @("-i", $IdentityFile)
}

# Check if ansible-playbook is available locally
$localAnsible = Get-Command ansible-playbook -ErrorAction SilentlyContinue

if ($localAnsible) {
    Write-Host "`n[Local Controller] Executing ansible-playbook locally..." -ForegroundColor Green
    Push-Location $AnsibleDir
    try {
        $ansibleArgs = @("-i", "inventory/hosts.yml", $Playbook)
        if ($Check) { $ansibleArgs += "--check" }
        if ($Tags.Count -gt 0) { $ansibleArgs += @("--tags", ($Tags -join ",")) }
        $env:SOPS_AGE_KEY_FILE = $AgeKeyFile
        & ansible-playbook @ansibleArgs
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    exit $exitCode
} else {
    Write-Host "`n[Remote Remoting] Native ansible-playbook not found on local Windows workstation." -ForegroundColor Yellow
    Write-Host "Syncing ansible project and orchestrating execution on $User@$HostAddress..." -ForegroundColor Cyan

    # 1. Test SSH connectivity
    Write-Host "Testing SSH connection to $User@$HostAddress..."
    $testResult = & ssh @sshOpts "$User@$HostAddress" "uname -s" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to connect to $User@$HostAddress over SSH: $testResult"
        exit 4
    }

    # 2. Ensure prerequisites on target host
    Write-Host "Checking target environment dependencies..."
    $checkCmd = "which ansible-playbook >/dev/null 2>&1 || sudo pacman -Sy --noconfirm --needed ansible-core sops age python-yaml"
    & ssh @sshOpts "$User@$HostAddress" $checkCmd
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to verify or install dependencies on target host."
        exit 2
    }

    # Ensure collections are installed on target
    & ssh.exe @sshOpts "$User@$HostAddress" "test -d ~/.ansible/collections/ansible_collections/community/sops || ansible-galaxy collection install community.sops ansible.posix community.general"

    # 3. Transfer age key if available locally
    if (Test-Path $AgeKeyFile) {
        Write-Host "Syncing age key to target host..."
        $keyBytes = [System.IO.File]::ReadAllBytes($AgeKeyFile)
        $b64 = [Convert]::ToBase64String($keyBytes)
        $remoteCmd = "mkdir -p -m 700 ~/.config/sops/age && echo '$b64' | base64 -d > ~/.config/sops/age/keys.txt && chmod 600 ~/.config/sops/age/keys.txt"
        & ssh @sshOpts "$User@$HostAddress" $remoteCmd
    }

    # Transfer Antigravity credentials from workstation if available locally
    $localOauth = Join-Path $env:USERPROFILE ".gemini\oauth_creds.json"
    $localAccounts = Join-Path $env:USERPROFILE ".gemini\google_accounts.json"
    if (Test-Path $localOauth) {
        Write-Host "Syncing Antigravity OAuth credentials to target host..."
        $oauthBytes = [System.IO.File]::ReadAllBytes($localOauth)
        $b64Oauth = [Convert]::ToBase64String($oauthBytes)
        $remoteOauthCmd = "mkdir -p -m 700 ~/.gemini && echo '$b64Oauth' | base64 -d > ~/.gemini/oauth_creds.json && chmod 600 ~/.gemini/oauth_creds.json"
        & ssh @sshOpts "$User@$HostAddress" $remoteOauthCmd
    }
    if (Test-Path $localAccounts) {
        Write-Host "Syncing Antigravity Google accounts to target host..."
        $accBytes = [System.IO.File]::ReadAllBytes($localAccounts)
        $b64Acc = [Convert]::ToBase64String($accBytes)
        $remoteAccCmd = "mkdir -p -m 700 ~/.gemini && echo '$b64Acc' | base64 -d > ~/.gemini/google_accounts.json && chmod 600 ~/.gemini/google_accounts.json"
        & ssh @sshOpts "$User@$HostAddress" $remoteAccCmd
    }

    # 4. Sync ansible/ directory via tar & scp
    Write-Host "Syncing Ansible workspace to /tmp/homelab2-ansible on target..."
    $tempArchive = [System.IO.Path]::GetTempFileName() + ".tar.gz"
    try {
        & tar.exe -czf "$tempArchive" -C "$RepoRoot" ansible
        & scp.exe @scpOpts "$tempArchive" "${User}@${HostAddress}:/tmp/ansible.tar.gz"
        $remoteUnpackCmd = "rm -rf /tmp/homelab2-ansible && mkdir -p /tmp/homelab2-ansible && tar -xzf /tmp/ansible.tar.gz -C /tmp/homelab2-ansible && rm -f /tmp/ansible.tar.gz"
        & ssh @sshOpts "$User@$HostAddress" $remoteUnpackCmd
    } finally {
        if (Test-Path $tempArchive) { Remove-Item -Force $tempArchive }
    }

    # 5. Run playbook on target host
    Write-Host "`nExecuting playbook on target host ($Playbook)..." -ForegroundColor Green
    $remoteArgs = "ansible-playbook -i inventory/hosts.yml $Playbook --connection=local"
    if ($Check) { $remoteArgs += " --check" }
    if ($Tags.Count -gt 0) { $remoteArgs += " --tags '$($Tags -join ',')'" }

    $execCmd = "cd /tmp/homelab2-ansible/ansible && export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt && export ANSIBLE_PIPELINING=False && export PYTHONMALLOC=malloc && $remoteArgs"
    & ssh @sshOpts "$User@$HostAddress" $execCmd
    $remoteExit = $LASTEXITCODE

    # Cleanup temporary synced directory
    & ssh @sshOpts "$User@$HostAddress" "rm -rf /tmp/homelab2-ansible"

    exit $remoteExit
}
