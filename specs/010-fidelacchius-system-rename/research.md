# Research & Technical Decisions: System Identity & Backup Bucket Naming (Fidelacchius)

**Feature**: `010-fidelacchius-system-rename`  
**Date**: 2026-11-04  
**Status**: Completed  

---

## Technical Context & Research Questions

This feature encompasses four distinct operational domains:
1. **Host Identity & Local Resolution**: Aligning the OS hostname and network identity to `fidelacchius`.
2. **Tailscale Node Identity & Funnel Ingress**: Reclaiming the canonical node name on the tailnet without numerical suffixes and updating Vaultwarden's Funnel domain.
3. **Offsite Backup Repository Migration**: Migrating from the temporary test bucket (`homelab2-fidelachius`) to the official Backblaze B2 bucket (`fidelacchius-backups`), initializing a clean Restic repository (`b2:fidelacchius-backups:fidelacchius`), and executing a restore verification drill.
4. **Ansible Inventory & Operator Script Alignment**: Updating `inventory/hosts.yml`, migrating `host_vars/homelab2/` to `host_vars/fidelacchius/`, and adjusting operator convergence scripts.

---

## Decision 1: Hostname Configuration & Local Resolution

### Decision
Use `hostnamectl set-hostname fidelacchius` to update both static and transient hostnames, and update `/etc/hosts` to map `127.0.1.1` and `127.0.0.1` to `fidelacchius` and `fidelacchius.localdomain`.

### Rationale
- `hostnamectl` interacts directly with `systemd-hostnamed`, updating `/etc/hostname` and propagating the new hostname to the kernel in real time without requiring a system reboot.
- Updating `/etc/hosts` prevents local resolution failures for applications relying on `getaddrinfo` or `gethostname`.
- Ensures shell prompts (`PS1`), systemd journal logs, and MotD display `fidelacchius` immediately on subsequent login sessions.

### Alternatives Considered
- *Direct file edit to `/etc/hostname` without `hostnamectl`*: Rejected because it requires a reboot or explicit `sysctl kernel.hostname=fidelacchius` to take effect in the active kernel session.
- *Preserving `homelab2` as an alias in `/etc/hosts`*: Acceptable as a transitional alias during migration, but the canonical mapping must resolve `fidelacchius`.

---

## Decision 2: Tailscale Node Renaming & Name Collision Mitigation

### Decision
1. Operator manually deletes the legacy offline `fidelacchius` device (`100.109.1.87`, last seen 27 days ago) from the Tailscale Admin Console.
2. Update the node identity on the target host by executing `tailscale set --hostname=fidelacchius` (or allowing Tailscale to adopt the new OS hostname automatically upon service reload).
3. Re-verify the node's MagicDNS FQDN (`fidelacchius.fable-mackarel.ts.net`).
4. Re-assert Funnel routing for Vaultwarden on port 443 -> internal port 8088.

### Rationale
- Tailscale guarantees unique MagicDNS hostnames. If a machine with hostname `fidelacchius` already exists in the tailnet, Tailscale appends a numeric suffix (e.g. `fidelacchius-1`). Deleting the stale legacy device first avoids collision and guarantees claiming `fidelacchius.fable-mackarel.ts.net`.
- `tailscale set --hostname=fidelacchius` explicitly sets the preferred tailnet machine name without requiring re-authentication or generating new auth keys.

### Alternatives Considered
- *`tailscale up --force-reauth`*: Rejected because it requires operator interaction or consuming a new single-use auth key, whereas `tailscale set` modifies preferences in-place on an already authenticated node.
- *Accepting `fidelacchius-1`*: Rejected because it violates the user's explicit requirement for an official, clean identity.

---

## Decision 3: Backblaze B2 Official Bucket & Restic Repository Cutover

### Decision
1. Update `vault_restic_repository` in `ansible/inventory/group_vars/all/vault.yml` (and template in `vault.yml.example`) to `b2:fidelacchius-backups:fidelacchius`.
2. Operator provisions a new Backblaze B2 Application Key (replacing the legacy key named `homelab` in the B2 portal) with read/write access to the `fidelacchius-backups` bucket. Update `vault_b2_account_id` and `vault_b2_account_key` in the local gitignored `ansible/inventory/group_vars/all/vault.yml`.
3. Ensure the Backblaze B2 bucket `fidelacchius-backups` is created using the new application key.
4. Initialize the Restic repository with `restic -r b2:fidelacchius-backups:fidelacchius init` using the existing encryption passphrase.
5. Deploy updated `/etc/homelab/backup.env` via Ansible backup role or direct configuration.
6. Trigger an immediate manual backup run via `/usr/local/bin/homelab-backup run` to create the initial baseline snapshot.
7. Perform an automated non-destructive restore drill using `/usr/local/bin/restore-from-b2.sh` to `/tmp/b2-test-restore` to verify data recovery integrity.
8. Once verified, document the procedure to retire/delete the legacy test bucket `homelab2-fidelachius` and delete the old `homelab` application key in the B2 console.

### Rationale
- Complies strictly with Constitution Principle V (Disaster Recovery & Backup by Design) and Principle IV (Zero Secrets in Version Control).
- A clean repository initialization ensures that no corrupt or inconsistent state from the test bucket is carried over.
- Running a test restore immediately confirms end-to-end viability before retiring the test bucket.

### Alternatives Considered
- *`restic copy` from old bucket to new bucket*: Rejected as unnecessary complexity; the homelab data is live on the system and a fresh initial backup directly to the new bucket creates a clean baseline while the old bucket remains available for archival until confirmed.
- *Renaming the bucket in B2*: B2 bucket names are globally unique and immutable once created; creating a new bucket is the standard procedure.

---

## Decision 4: Vaultwarden & Funnel Public Ingress Transition

### Decision
1. Update `vaultwarden_domain` dynamically via the existing role logic in `ansible/roles/vaultwarden/tasks/config.yml` (which queries `tailscale status --json` for `CertDomains` or `DNSName`), or configure `https://fidelacchius.fable-mackarel.ts.net`.
2. Re-render `/opt/services/vaultwarden/.env` with `DOMAIN=https://fidelacchius.fable-mackarel.ts.net`.
3. Restart the Vaultwarden container (`docker compose up -d --force-recreate`).
4. Ensure Tailscale Funnel is listening and routing public traffic for `https://fidelacchius.fable-mackarel.ts.net` to port 8088.

### Rationale
- Vaultwarden uses the `DOMAIN` variable for WebCrypto, U2F/FIDO2 webauthn credentials, and invitation/email links. Mismatches between incoming Host headers and `DOMAIN` can trigger security warnings or login failures in Bitwarden clients.
- Existing Ansible role logic already handles dynamic FQDN discovery; once Tailscale claims `fidelacchius.fable-mackarel.ts.net`, the role automatically converges the configuration.

### Alternatives Considered
- *Hardcoding `vaultwarden_domain` in `group_vars/all/vars.yml`*: While valid, leaving it dynamic or setting it to the exact domain works cleanly. We will ensure the dynamic fallback resolves to `fidelacchius.fable-mackarel.ts.net` and document the expected domain in `vars.yml.example` and documentation.

---

## Decision 5: Ansible Inventory & Script Alignment

### Decision
1. In `ansible/inventory/hosts.yml`: Rename host entry `homelab2` to `fidelacchius`.
2. In `ansible/inventory/host_vars/`: Rename directory `homelab2` to `fidelacchius` (`host_vars/fidelacchius/storage.yml`).
3. In `ansible/playbooks/site.yml` and sub-playbooks: Ensure play targets match `all` or `homelab_nodes`.
4. In `scripts/apply-*.sh`, `scripts/apply-*.ps1`, `scripts/verify-*.sh`, `scripts/verify-*.ps1`: Update default target host descriptions and verify script target labels from `homelab2` to `fidelacchius`.
5. Preserve internal platform paths (`/etc/homelab`, `/opt/services`, `homelab-backup.service`, `/etc/udev/rules.d/99-homelab-peripherals.rules`) per specification to minimize disruption.

### Rationale
- Complies with Constitution Principle I (Declarative-First Automation) and Principle II (Idempotency).
- Ansible matches `host_vars/<inventory_hostname>/` to host definitions in `hosts.yml`. If `hosts.yml` defines `fidelacchius` but variables are in `host_vars/homelab2/`, storage and host-specific variables will not be loaded.
- Preserving `/etc/homelab` avoids unnecessary service migrations and breaking existing file paths.

### Alternatives Considered
- *Alias `homelab2` in inventory*: Rejected because keeping the legacy name creates ongoing confusion and technical debt.
