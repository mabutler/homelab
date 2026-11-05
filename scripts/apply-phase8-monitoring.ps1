<#
.SYNOPSIS
    Cross-platform PowerShell runner for fidelacchius Phase 8 (Platform Monitoring & Alerting: ntfy & Healthchecks).
.DESCRIPTION
    Orchestrates execution of Ansible playbooks against the production host.
    Supports native push if ansible-playbook is installed locally, or automated
    SSH sync & remote execution if running from a Windows operator workstation.
.PARAMETER HostAddress
    Target IP address or hostname (default: 192.168.4.57).
.PARAMETER User
    Remote administrative SSH username (default: admin).
.PARAMETER IdentityFile
    Path to private SSH key for authentication.
.PARAMETER Playbook
    Ansible playbook to execute relative to ansible/ (default: playbooks/monitoring.yml).
.PARAMETER Tags
    Optional array of tags to filter execution.
.PARAMETER Check
    Perform a dry run / check mode (no changes committed).
#>
[CmdletBinding()]
param(
    [string]$HostAddress = "192.168.4.57",
    [string]$User = "admin",
    [string]$IdentityFile = "",
    [string]$Playbook = "playbooks/monitoring.yml",
    [string[]]$Tags = @(),
    [switch]$Check
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$AnsibleDir = Join-Path $RepoRoot "ansible"

Write-Host "=== fidelacchius Phase 8 Platform Monitoring Convergence Orchestrator (PowerShell) ===" -ForegroundColor Cyan
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

if (Get-Command ansible-playbook -ErrorAction SilentlyContinue) {
    Write-Host "`n[Local Controller] Executing ansible-playbook locally..." -ForegroundColor Green
    Set-Location $AnsibleDir
    $ansibleArgs = @("-i", "inventory/hosts.yml", $Playbook)
    if ($Check) { $ansibleArgs += "--check" }
    if ($Tags.Count -gt 0) { $ansibleArgs += @("--tags", ($Tags -join ",")) }
    & ansible-playbook @ansibleArgs
    exit $LASTEXITCODE
} else {
    Write-Host "`n[Remote Remoting] Native ansible-playbook not found on local controller." -ForegroundColor Yellow
    Write-Host "Syncing ansible project and orchestrating execution on $User@$HostAddress..."

    & ssh @sshOpts "$User@$HostAddress" "uname -s" | Out-Null

    $tarFile = [System.IO.Path]::GetTempFileName() + ".tar"
    try {
        Set-Location $RepoRoot
        tar -cf $tarFile ansible scripts
        & scp @scpOpts $tarFile "$User@${HostAddress}:/tmp/homelab2-ansible.tar"

        $remoteSetupCmd = "rm -rf /tmp/homelab2-ansible && mkdir -p /tmp/homelab2-ansible && tar -xf /tmp/homelab2-ansible.tar -C /tmp/homelab2-ansible && rm -f /tmp/homelab2-ansible.tar"
        & ssh @sshOpts "$User@$HostAddress" $remoteSetupCmd

        $remotePlaybookCmd = "cd /tmp/homelab2-ansible/ansible && ansible-playbook -i inventory/hosts.yml $Playbook --connection=local"
        if ($Check) { $remotePlaybookCmd += " --check" }
        if ($Tags.Count -gt 0) { $remotePlaybookCmd += " --tags '$($Tags -join ',')'" }

        Write-Host "`nExecuting playbook on target host ($Playbook)..." -ForegroundColor Green
        & ssh -t @sshOpts "$User@$HostAddress" $remotePlaybookCmd
        $remoteExit = $LASTEXITCODE

        & ssh @sshOpts "$User@$HostAddress" "rm -rf /tmp/homelab2-ansible"
        exit $remoteExit
    } finally {
        if (Test-Path $tarFile) { Remove-Item -Force $tarFile }
    }
}
