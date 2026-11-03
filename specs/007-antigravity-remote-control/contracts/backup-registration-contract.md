# Contract: Antigravity Backup Registration & Disaster Recovery

**Contract Identifier**: `AG-BACKUP-V1`  
**Target Host**: `admin@192.168.4.57` (`homelab2`)  
**Backup Engine**: `restic` to Backblaze B2  

---

## 1. Backup Manifest Registration

### 1.1 Inclusions (`/etc/homelab/backup-include.txt`)
The following paths MUST be registered in `/etc/homelab/backup-include.txt`:
```text
/home/admin/.gemini/oauth_creds.json
/home/admin/.gemini/google_accounts.json
/home/admin/.gemini/antigravity-cli/settings.json
/home/admin/.ssh/id_ed25519_github
/home/admin/.ssh/id_ed25519_github.pub
```

### 1.2 Exclusions (`/etc/homelab/backup-excludes.txt`)
The following transient and cache directories MUST be registered in `/etc/homelab/backup-excludes.txt`:
```text
/home/admin/.gemini/antigravity-cli/cache/**
/home/admin/.gemini/antigravity-cli/crashes/**
/home/admin/.gemini/antigravity-cli/log/**
/home/admin/.gemini/antigravity-cli/updater/**
/home/admin/.gemini/antigravity-cli/brain/**
/home/admin/.gemini/tmp/**
/home/admin/homelab2/.git/**
```

---

## 2. Disaster Recovery & Profile Restoration

### 2.1 Restoration Procedure
During disaster recovery on a clean machine:
1. `scripts/restore-from-b2.sh` executes using the 4 bootstrap credentials.
2. The restored snapshot recreates `/home/admin/.gemini/` and `/home/admin/.ssh/`.
3. File permissions are restored:
   - `/home/admin/.gemini/oauth_creds.json` -> `0600 admin:admin`
   - `/home/admin/.gemini/google_accounts.json` -> `0600 admin:admin`
   - `/home/admin/.gemini/antigravity-cli/settings.json` -> `0600 admin:admin`
   - `/home/admin/.ssh/id_ed25519_github` -> `0600 admin:admin`
4. Rerunning `scripts/apply-phase7-antigravity.sh` reinstalls the binary if missing, activates user lingering, starts `agy-remote-control.service`, and clones the workspace without requiring interactive browser authentication.

### 2.2 Verification of Backup Integrity
- The automated verification suite asserts that `/home/admin/.gemini/oauth_creds.json` and `settings.json` are present in the latest Restic snapshot index.
- Live caches and transient `.git` object trees are confirmed absent from the snapshot paths.
