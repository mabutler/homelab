# Contract: Secrets & SOPS Vault Schema

**Feature**: Core Hardening & Configuration Management Foundation  
**Branch**: `002-core-hardening-iac`  
**Date**: 2026-11-01  

This contract defines the format, encryption standards, recipient public key requirements, and variable definitions for secrets managed in Phase 2.

---

## 1. Cryptographic Standards

- **Encryption Tool**: SOPS (Secrets OPerationS) v3.8+
- **Asymmetric Key Primitive**: `age` (X25519 Curve25519 key exchange, ChaCha20-Poly1305 symmetric cipher)
- **Key File Standard**: Operator age identity file storing the private key:
  ```text
  # public key: age1...
  AGE-SECRET-KEY-1...
  ```
- **Configuration File (`.sops.yaml`)**:
  Placed at repository root or `ansible/.sops.yaml` to specify encryption rules:
  ```yaml
  creation_rules:
    - path_regex: .*\.sops\.ya?ml$
      age: "age1d8h44h8...[OPERATOR_AGE_PUBLIC_KEY]"
  ```

---

## 2. Vault File Structure (`vault.sops.yml`)

Located at `ansible/inventory/group_vars/all/vault.sops.yml`.

### Plaintext Schema (Decrypted View):

```yaml
# Encrypted host and administrative secrets
vault_admin_username: "admin"

# Password hash for emergency console login (optional / locked by default)
vault_admin_password_hash: "$6$rounds=656000$..."

# Authorized public keys for administrative login
vault_admin_authorized_keys:
  - "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... operator@workstation"

# Future secret tokens (reserved for Phase 3/5)
vault_tailscale_auth_key: "tskey-auth-..."
```

### Encrypted Schema (Repository / At-Rest View):

```yaml
vault_admin_username: ENC[AES256_GCM,data:...,iv:...,tag:...]
vault_admin_password_hash: ENC[AES256_GCM,data:...,iv:...,tag:...]
vault_admin_authorized_keys:
  - ENC[AES256_GCM,data:...,iv:...,tag:...]
sops:
  kms: []
  gcp_kms: []
  azure_kv: []
  hc_vault: []
  age:
    - recipient: age1...
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        ...
        -----END AGE ENCRYPTED FILE-----
  lastmodified: "2026-11-01T15:00:00Z"
  mac: ENC[AES256_GCM,...]
  version: 3.9.0
```

---

## 3. Operations Contract

### 3.1 Creating or Editing Secrets

```bash
# Edit vault in-place with default editor
sops ansible/inventory/group_vars/all/vault.sops.yml

# Encrypt a new file
sops --encrypt --in-place ansible/inventory/group_vars/all/vault.sops.yml
```

### 3.2 Automated Git Leak Prevention

- Pre-commit hooks (`.pre-commit-config.yaml` or git hook scripts) MUST execute `git diff --cached` check ensuring no unencrypted files matching `*vault*` or unencrypted secrets are staged.
- SOPS files MUST have valid `sops.mac` metadata to be committed.
