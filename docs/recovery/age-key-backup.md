# Disaster Recovery & Key Backup Procedure: SOPS Master Age Key

**Subsystem**: Infrastructure Secrets Management & Cryptography  
**Classification**: Operational Security (OpSec) & Disaster Recovery  
**Applicability**: `homelab2` Bare-Metal Platform  

---

## 1. Cryptographic Security Model

Configuration secrets, credentials, and host variables are encrypted at rest using **SOPS** with **age asymmetric encryption** (X25519 Curve25519 key exchange, ChaCha20-Poly1305 symmetric cipher).

- **Public Key** (`age1...`):
  Non-sensitive. Tracked in `.sops.yaml` creation rules and embedded within `vault.sops.yml` file metadata.
- **Private Master Key** (`AGE-SECRET-KEY-1...`):
  Highly sensitive. **NEVER** committed to version control, stored on unencrypted cloud drives, or shared over plaintext channels. Possession of this key grants decryption rights to all vaulted secrets.

Loss of the master age private key without an out-of-band backup renders vaulted configuration secrets unrecoverable.

---

## 2. Key Generation & Initial Setup

To generate a new age keypair on an administrative operator workstation:

```bash
# Create local secure directory
mkdir -p -m 700 ~/.config/sops/age

# Generate keypair
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt

# Inspect public recipient key (age1...)
age-keygen -y ~/.config/sops/age/keys.txt
```

Set the environment variable in your shell profile (`~/.bashrc` or `~/.zshrc`):
```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

---

## 3. Out-Of-Band Backup Procedures

To guarantee disaster recovery resilience without relying on off-host cloud services (per Constitution Principle V & Phase 2 Early Exemption), operators MUST maintain at least two out-of-band backup copies:

### 3.1 Primary: Encrypted Cold Offline Media (Air-Gapped USB)
1. Format a dedicated USB flash drive with an encrypted filesystem (LUKS on Linux, VeraCrypt, or encrypted APFS/BitLocker).
2. Copy `keys.txt` to the encrypted volume:
   ```bash
   cp ~/.config/sops/age/keys.txt /mnt/encrypted-usb/homelab2-age-keys.txt
   ```
3. Safely unmount and store the drive in a secure, fireproof safe.

### 3.2 Secondary: Physical Paper / Cold Storage
1. Print or transcribe the 60-character `AGE-SECRET-KEY-1...` string or generate an offline paper QR code:
   ```bash
   # Optional QR code generation (offline)
   qrencode -t PNG -o age-key-qr.png < ~/.config/sops/age/keys.txt
   ```
2. Place the paper copy in an opaque sealed envelope in physical safe custody.

### 3.3 Tertiary: Password Vault Secure Note
Store a copy of the private key text in an end-to-end encrypted password manager (e.g., Bitwarden / 1Password) under an entry titled `homelab2 - SOPS Age Master Key`.

---

## 4. Disaster Recovery & Restoration Verification

In the event of operator workstation loss or platform re-installation:

### Step 1: Restore the Key File
Retrieve the key from offline storage and write to `~/.config/sops/age/keys.txt`:
```bash
mkdir -p -m 700 ~/.config/sops/age
# Copy or paste contents
chmod 600 ~/.config/sops/age/keys.txt
```

### Step 2: Set Environment Variable
```bash
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
```

### Step 3: Validate Decryption Capability
Run a test decryption against the tracked vault:
```bash
sops -d ansible/inventory/group_vars/all/vault.sops.yml
```
**Verification Success**: The command exits with code 0 and displays the decrypted YAML payload without cryptographic MAC errors.

---

## 5. Key Rotation Procedure

If the master age private key is compromised or needs periodic rotation:

1. Generate a new keypair:
   ```bash
   age-keygen -o ~/.config/sops/age/keys-new.txt
   NEW_PUBKEY=$(age-keygen -y ~/.config/sops/age/keys-new.txt)
   ```
2. Update `.sops.yaml` with the new public key:
   ```yaml
   creation_rules:
     - path_regex: .*\.sops\.ya?ml$
       age: "<NEW_PUBKEY>"
   ```
3. Re-encrypt existing vault files with the new recipient:
   ```bash
   sops updatekeys ansible/inventory/group_vars/all/vault.sops.yml
   ```
4. Commit the re-encrypted `vault.sops.yml` and `.sops.yaml` to git.
5. Replace the active key file:
   ```bash
   mv ~/.config/sops/age/keys-new.txt ~/.config/sops/age/keys.txt
   ```
6. Update out-of-band backups following Section 3.
