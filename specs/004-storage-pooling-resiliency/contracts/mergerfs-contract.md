# Contract: MergerFS Storage Pooling Specification

**Feature**: `specs/004-storage-pooling-resiliency`  
**File**: `contracts/mergerfs-contract.md`  
**Status**: Active  

---

## 1. Pool Mount Definition

The unified pool MUST be declared in `/etc/fstab` using MergerFS FUSE syntax:

```text
/mnt/disks/data*    /mnt/storage    fuse.mergerfs    defaults,nonempty,allow_other,use_ino,cache.files=partial,dropcacheonclose=true,category.create=mfs,func.mkdir=pmfs,minfreespace=50G,atomic_rename=true,fsname=storage_pool,nofail,x-systemd.requires-mounts-for=/mnt/disks/data1    0  0
```

---

## 2. Parameter Specifications & Contracts

| Parameter | Value | Functional Purpose & Contract |
|---|---|---|
| **Source Branches** | `/mnt/disks/data*` | Aggregates all underlying data disks. Parity (`/mnt/disks/parity*`) and scratch (`/mnt/scratch`) disks MUST NOT match this glob. |
| **Mount Point** | `/mnt/storage` | Unified virtual mount target. |
| **FUSE Type** | `fuse.mergerfs` | Standard MergerFS FUSE driver. |
| `allow_other` | Required | Permits non-root services and containers to read and write to the pool. |
| `use_ino` | Required | Tells MergerFS to supply stable inode numbers, preventing inode collisions across member disks. |
| `cache.files` | `partial` | Enables mmap support (necessary for SQLite and database processes) while preventing unbounded memory consumption. |
| `dropcacheonclose` | `true` | Releases kernel page cache when files are closed, keeping host RAM free for application containers. |
| `category.create` | `mfs` | Most Free Space: New files are written to whichever member disk currently possesses the most available free space. |
| `func.mkdir` | `pmfs` | Path-preserving Most Free Space: Creates directories on the member disk with the most free space while respecting directory organization. |
| `minfreespace` | `50G` | When a member drive reaches 50GB or less of free space, MergerFS halts new file allocation to that drive and writes to remaining drives. |
| `atomic_rename` | `true` | Makes renames atomic across paths on the same underlying branch; enables instant hardlinks and moves for media managers without file duplication. |
| `fsname` | `storage_pool` | Assigns a clear virtual device identifier visible in `df -h` and `mount`. |
| `x-systemd.requires-mounts-for` | Member disk paths | Declares explicit systemd mount ordering so the pool only mounts after underlying physical data drives are mounted. |
| `nofail` | Required | Prevents boot hangs if one drive is absent. |

---

## 3. Operational Guarantees

1. **Independent Spin-Down**: Reading a file from `/mnt/storage` will spin up ONLY the underlying physical disk where that file resides. All other member disks stay in standby.
2. **Transparent Read Failover**: If a file exists on `/mnt/disks/data1/media/movie.mkv`, it appears at `/mnt/storage/media/movie.mkv` with identical metadata, permissions, and timestamps.
3. **Capacity Aggregation**: Total capacity of `/mnt/storage` equals the arithmetic sum of free and used space across all active member data disks.
