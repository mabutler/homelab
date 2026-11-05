# Quickstart & Validation Guide: Automated Platform Monitoring & Alerting (`ntfy` & `Healthchecks`)

**Feature**: `011-monitoring-ntfy-healthchecks`  
**Date**: 2026-11-05  
**Spec**: [spec.md](./spec.md) | **Data Model**: [data-model.md](./data-model.md) | **Contracts**: [contracts/](./contracts/)

---

## 1. Prerequisites & Minimal One-Time Bootstrap

1. **External Cloud Setup (One-Time, < 2 Minutes)**:
   - Subscribe to your chosen private topic in the `ntfy.sh` mobile/web app (e.g., `fidelacchius-alerts-<random-suffix>`).
   - Create a project in `https://healthchecks.io`, add an `ntfy` integration under **Integrations** pointing to your `ntfy.sh` topic, and copy the project's **API Key (Read/Write)**.
2. **Populate Local Secrets (`ansible/inventory/group_vars/all/vault.yml`)**:
   Add the bootstrap variables defined in [data-model.md § 2.1](./data-model.md):
   ```yaml
   vault_ntfy_server_url: "https://ntfy.sh"
   vault_ntfy_topic: "fidelacchius-alerts-<your-secret-suffix>"
   vault_ntfy_token: ""  # Optional ntfy access token (tk_...)
   vault_healthchecks_api_key: "<your-healthchecks-rw-api-key>"
   vault_healthchecks_ping_key: ""  # Optional; auto-resolved via API v3 if omitted
   ```

---

## 2. Deployment & Zero-Touch Provisioning

Run the monitoring deployment wrapper (or Ansible playbook) from the repository root:

```bash
# Using the Bash convergence wrapper
./scripts/apply-phase8-monitoring.sh

# Or directly via ansible-playbook
cd ansible
ansible-playbook playbooks/monitoring.yml
```

*(From a Windows workstation, run `.\scripts\apply-phase8-monitoring.ps1`.)*

**Expected Outcome**:
- `/etc/homelab/monitoring.env` (`0600`) and `/etc/homelab/monitoring/checks-catalog.json` are rendered.
- `/usr/local/bin/homelab-hc-reconcile` automatically creates/updates all 6 canonical checks in `healthchecks.io` with `channels: "*"` and caches their ping URLs in `/var/lib/homelab/monitoring/checks.json`.
- Global systemd failure hooks (`service.d/99-homelab-failure-alert.conf`), scheduled job drop-ins (`10-healthchecks.conf`), `smartd` alert hooks, and `homelab-heartbeat.timer` are active.

---

## 3. End-to-End Validation Scenarios

### Scenario A: Zero-Touch Check Provisioning & Composite Heartbeat (User Stories 2 & 3)

Verify that all 6 platform checks are provisioned in `healthchecks.io` and that the composite health sweep reports `up`:

```bash
# 1. Re-run reconciliation idempotently and inspect cached checks
sudo /usr/local/bin/homelab-hc-reconcile
sudo jq 'keys' /var/lib/homelab/monitoring/checks.json

# 2. Trigger an immediate composite health sweep & heartbeat ping
sudo systemctl start homelab-heartbeat.service
journalctl -u homelab-heartbeat.service -n 20 --no-pager
```

**Expected Outcome**:
- `checks.json` lists all 6 canonical slugs (`fidelacchius-host-heartbeat`, `fidelacchius-backup-daily`, `fidelacchius-backup-check`, `fidelacchius-vaultwarden-backup`, `fidelacchius-snapraid-sync`, `fidelacchius-snapraid-scrub`).
- `homelab-heartbeat.service` exits `0`, silently pings `fidelacchius-host-heartbeat` (`up` in `healthchecks.io`), and sends zero `ntfy.sh` notifications while healthy.

---

### Scenario B: Global Catch-All Service Failure Alert (User Story 1)

Verify that any failing systemd service automatically triggers a push notification to `ntfy.sh` with unit diagnostics within 30 seconds:

```bash
# Trigger a transient synthetic systemd service failure
sudo systemd-run --unit=homelab-synthetic-fail-test.service /bin/sh -c "echo 'Synthetic error log line for monitoring test' >&2; exit 42" || true

# Inspect the automatically triggered homelab-alert@ instance
journalctl -u "homelab-alert@homelab-synthetic-fail-test.service" -n 25 --no-pager
```

**Expected Outcome**:
- `OnFailure=homelab-alert@%n.service` fires automatically without any unit-specific monitoring config.
- A high-priority notification titled `[FAILURE] fidelacchius: homelab-synthetic-fail-test.service (system)` containing exit status `42` and the stderr log line arrives on your `ntfy.sh` topic within seconds.
- Clean up the transient failed unit state and send recovery with:
  ```bash
  sudo systemctl reset-failed homelab-synthetic-fail-test.service
  sudo /usr/local/bin/homelab-ntfy --component "unit-system-homelab-synthetic-fail-test.service" --status ok --title "Synthetic test cleared" --message "Synthetic test unit reset."
  ```

---

### Scenario C: Alert Deduplication & Recovery State Machine (Edge Case 2 & SC-004)

Verify that 5 consecutive failures within the cooldown window generate only 1 failure notification and 1 recovery notification:

```bash
# Simulate 5 rapid failures for a flapping component
for i in 1 2 3 4 5; do
  sudo /usr/local/bin/homelab-ntfy \
    --component "test-flap-demo" \
    --status failing \
    --title "[FAILURE] fidelacchius: test-flap-demo" \
    --message "Simulated crash loop iteration ${i}"
done

# Inspect deduplication state (expect suppressed_count: 4)
sudo cat /var/lib/homelab/monitoring/state/test-flap-demo.json | jq .

# Simulate component recovery
sudo /usr/local/bin/homelab-ntfy \
  --component "test-flap-demo" \
  --status ok \
  --title "[RECOVERED] fidelacchius: test-flap-demo" \
  --message "Component stabilized"
```

**Expected Outcome**:
- The operator receives 1 initial failure notification, 4 duplicate calls are suppressed (`suppressed_count == 4`), and 1 `[RECOVERED]` notification is delivered when `--status ok` is signaled.

---

### Scenario D: Automated Acceptance Suite (`MON-01` to `MON-10`)

Run the full automated verification suite defined in [verification-contract.md](./contracts/verification-contract.md):

```bash
# Run standalone verification script
sudo ./scripts/verify-phase8-monitoring.sh

# Or run the Ansible verification playbook
cd ansible
ansible-playbook playbooks/verify-phase8-monitoring.yml
```

**Expected Outcome**: All 10 checks (`MON-01` through `MON-10`) report `PASS`.
