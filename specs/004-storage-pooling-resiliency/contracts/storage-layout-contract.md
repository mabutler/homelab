# Contract: Storage Layout & Mount Hierarchy

**Feature**: `specs/004-storage-pooling-resiliency`  
**File**: `contracts/storage-layout-contract.md`  
**Status**: Active  

---

## 1. Directory Structure Contract

The host system MUST adhere to the following directory hierarchy:

```text
/
├── opt/
│   └── services/                 # Fast NVMe app tier (configs, databases, runtime state)
└── mnt/
    ├── disks/
    │   ├── data1/                # Underlying physical data disk 1
    │   ├── data2/                # Underlying physical data disk 2
    │   └── parity1/              # Underlying physical parity disk 1
    ├── storage/                  # MergerFS pooled virtual mount point (/mnt/disks/data*)
    └── scratch/                  # Isolated non-parity scratch storage (CCTV, downloads)
```

---

## 2. Mount Point & `/etc/fstab` Specifications

All physical drives MUST be mounted by immutable filesystem UUID in `/etc/fstab` with the following flags:

```text
# Physical Bulk Data Disks
UUID=<data1-uuid>    /mnt/disks/data1    ext4    defaults,noatime,nofail,x-systemd.device-timeout=10s    0  2
UUID=<data2-uuid>    /mnt/disks/data2    ext4    defaults,noatime,nofail,x-systemd.device-timeout=10s    0  2

# Physical Parity Disk
UUID=<parity1-uuid>  /mnt/disks/parity1  ext4    defaults,noatime,nofail,x-systemd.device-timeout=10s    0  2

# Dedicated Scratch Disk / Partition
UUID=<scratch-uuid>  /mnt/scratch        ext4    defaults,noatime,nofail,x-systemd.device-timeout=10s    0  2
```

### Safety Flags:
- `noatime`: Disables access time writes, reducing wear on SSDs and spin-up events on spinning HDDs.
- `nofail`: Prevents boot hangs in headless environments if a drive fails to spin up or is disconnected.
- `x-systemd.device-timeout=10s`: Limits systemd boot wait to 10 seconds per storage disk before proceeding.

---

## 3. Ownership & Permissions Model

To eliminate multi-container file permission conflicts, the system enforces the following permissions contract:

| Target Path | Owner User | Owner Group | Mode | Description |
|---|---|---|---|---|
| `/opt/services` | `admin` (UID 1000) | `storage` (GID 1001) | `0775` | Base app directory; container directories inherit group permissions |
| `/mnt/storage` | `admin` (UID 1000) | `storage` (GID 1001) | `2775` | Setgid bit ensures all created subdirectories inherit `storage` group |
| `/mnt/scratch` | `admin` (UID 1000) | `storage` (GID 1001) | `2775` | Setgid bit enables shared write access across CCTV and download tools |
| `/mnt/disks/*` | `root` (UID 0) | `root` (GID 0) | `0755` | Raw physical mount points protected from direct unpooled tampering |

### User Group Membership:
- User `admin` MUST belong to group `storage` (GID 1001).
- Container services running as `PUID=1000` and `PGID=1001` possess full read/write privileges across the pool.
