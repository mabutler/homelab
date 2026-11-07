<#
.SYNOPSIS
    Cross-platform PowerShell runner for homelab2 Phase 5 (Immich Photo Management Platform Deployment).
.DESCRIPTION
    Orchestrates execution of Ansible playbooks against the production host.
    Supports native push if ansible-playbook is installed locally, or automated
    SSH sync & remote execution if running from a Windows operator workstation.
.PARAMETER TargetHost
    Target IP address or hostname (default: 192.168.4.57).
.PARAMETER User
    Remote administrative SSH username (default: admin).
.PARAMETER IdentityFile
    Path to private SSH key for authentication.
.PARAMETER Playbook
    Ansible playbook to execute relative to ansible/ (default: playbooks/immich.yml).
.PARAMETER Tags
    Optional array of tags to filter execution.
.PARAMETER Check
    Perform a dry run / check mode (no changes committed).
.PARAMETER AgeKeyFile
    Path to operator SOPS age private key file.
#>
[CmdletBinding()]
param(
    [Alias("HostAddress")]
    [string]$TargetHost = "192.168.4.57",
    [string]$User = "admin",
    [string]$IdentityFile = "",
    [string]$Playbook = "playbooks/immich.yml",
    [string[]]$Tags = @(),
    [switch]$Check,
    [string]$AgeKeyFile = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$AnsibleDir = Join-Path $RepoRoot "ansible"

# Resolve age key file
if (-not $AgeKeyFile) {
    if ($env:SOPS_AGE_KEY_FILE) {
        $AgeKeyFile = $env:SOPS_AGE_KEY_FILE
    } else {
        $AgeKeyFile = Join-Path $env:USERPROFILE ".config\sops\age\keys.txt"
    }
}

Write-Host "=== homelab2 Phase 5 Immich Convergence Orchestrator (PowerShell) ===" -ForegroundColor Cyan
Write-Host "Target Host : $User@$TargetHost"
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
        if ($LASTEXITCODE -ne 0) {
            throw "ansible-playbook failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "`n[Remote Remoting] Native ansible-playbook not found on local controller." -ForegroundColor Yellow
    Write-Host "Syncing ansible project and orchestrating execution on $User@$TargetHost..."

    # Test SSH connectivity
    & ssh @sshOpts "$User@$TargetHost" "uname -s" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to connect to $User@$TargetHost via SSH"
    }

    # Sync age key if present locally
    if (Test-Path $AgeKeyFile) {
        Write-Host "Syncing age key to target host..."
        Get-Content $AgeKeyFile -Raw | & ssh @sshOpts "$User@$TargetHost" "mkdir -p -m 700 ~/.config/sops/age && cat > ~/.config/sops/age/keys.txt && chmod 600 ~/.config/sops/age/keys.txt"
    }

    # Package and sync workspace
    $tarPath = [System.IO.Path]::GetTempFileName() + ".tar.gz"
    try {
        Write-Host "Packaging Ansible workspace..."
        Push-Location $RepoRoot
        tar -czf $tarPath ansible scripts
        Pop-Location

        Write-Host "Deploying workspace archive to target host..."
        & scp @scpOpts $tarPath "$User@${TargetHost}:/tmp/homelab2-ansible.tar.gz"

        $remoteSetup = "rm -rf /tmp/homelab2-ansible && mkdir -p /tmp/homelab2-ansible && tar -xzf /tmp/homelab2-ansible.tar.gz -C /tmp/homelab2-ansible && rm -f /tmp/homelab2-ansible.tar.gz"
        & ssh @sshOpts "$User@$TargetHost" $remoteSetup

        Write-Host "`nExecuting playbook on target host ($Playbook)..." -ForegroundColor Green
        $remotePlaybookCmd = "cd /tmp/homelab2-ansible/ansible && export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt && export ANSIBLE_PIPELINING=False && ansible-playbook -i inventory/hosts.yml $Playbook --connection=local"
        if ($Check) { $remotePlaybookCmd += " --check" }
        if ($Tags.Count -gt 0) { $remotePlaybookCmd += " --tags '$($Tags -join ',')'" }

        & ssh @sshOpts -t "$User@$TargetHost" $remotePlaybookCmd
        $remoteExit = $LASTEXITCODE

        & ssh @sshOpts "$User@$TargetHost" "rm -rf /tmp/homelab2-ansible"
        if ($remoteExit -ne 0) {
            throw "Remote execution of playbook failed with exit code $remoteExit"
        }
    } finally {
        if (Test-Path $tarPath) { Remove-Item -Force $tarPath }
    }
}
