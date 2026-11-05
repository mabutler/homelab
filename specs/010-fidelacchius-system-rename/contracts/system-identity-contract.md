# Contract: System Identity & Hostname Resolution

**Contract ID**: `SYSTEM-IDENTITY-V1`  
**Feature**: `010-fidelacchius-system-rename`  
**Status**: Active  

---

## 1. Operating System Hostname

The host MUST provide the following identity interfaces:

### 1.1 Static & Transient Hostname
- **Command**: `hostnamectl status` / `uname -n`
- **Expected Value**: `fidelacchius`
- **Configuration File**: `/etc/hostname`
- **File Contents**: Exactly `fidelacchius\n` (mode `0644 root:root`)

### 1.2 Pretty Hostname (Optional Informational)
- **Configuration**: `hostnamectl set-hostname --pretty "Fidelacchius (the sword of faith)"`
- **Configuration File**: `/etc/machine-info`

---

## 2. Local Loopback Resolution

The `/etc/hosts` file MUST maintain loopback resolution for the new canonical hostname to prevent `getaddrinfo(3)` resolution stalls:

### 2.1 Configuration Format (`/etc/hosts`)
```text
127.0.0.1   localhost
::1         localhost ip6-localhost ip6-loopback
127.0.1.1   fidelacchius.localdomain fidelacchius
```

### 2.2 Verification Command
```bash
getent hosts fidelacchius
# Expected output: 127.0.1.1 fidelacchius.localdomain fidelacchius (or 127.0.0.1)
```

---

## 3. Shell Prompt & Session Contract

- Interactive shell sessions (`/bin/bash`) using standard PS1 formats (`\u@\h:\w\$`) MUST display `admin@fidelacchius` upon new session creation.
