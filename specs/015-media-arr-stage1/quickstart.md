# Quickstart & Verification Guide: Media & Arr Stack — Stage 1

**Feature**: `015-media-arr-stage1`  
**Date**: 2026-11-17  
**Status**: Ready  

This guide provides step-by-step instructions for configuring **Tailscale Mullvad VPN / Exit Node** access, populating `vault.yml`, converging Stage 1 of the Media & Arr Stack (`arr_vpn`, `arr_qbittorrent`, `arr_jellyfin`) on `fidelacchius`, executing the 10-point automated acceptance suite, onboarding Jellyfin and qBittorrent, and verifying online backups.

---

## 1. Prerequisites & Required Tailscale Configuration

Because you use **WireGuard through Tailscale (Mullvad VPN add-on or a Tailscale Exit Node)** while host `fidelacchius` simultaneously runs **Tailscale Funnel on port 443 for Vaultwarden**, Stage 1 runs a dedicated Tailscale container (`arr_vpn`, hostname `fidelacchius-arr-vpn`) that routes only `arr_qbittorrent` traffic through the Mullvad exit node while keeping the host's own `tailscaled` completely unaffected.

### Step 1.1: Enable Mullvad Exit Node Access in Tailscale Admin Console

By default, a new Tailscale node cannot see Mullvad exit nodes (`tailscale exit-node list` returns `no exit nodes found`) until it is granted Mullvad access in the Tailscale Admin Console:

1. **Recommended (Tag-Based Auto-Grant via Access Controls)**:
   - Open **[Tailscale Admin Console -> Access Controls](https://login.tailscale.com/admin/acls)**.
   - Ensure `tag:arr-vpn` is defined under `tagOwners` and add `"mullvad"` to `nodeAttrs` so the `fidelacchius-arr-vpn` container automatically receives Mullvad exit-node access upon authentication:
     ```json
     "tagOwners": {
       "tag:arr-vpn": ["autogroup:admin"]
     },
     "nodeAttrs": [
       {
         "target": ["tag:arr-vpn", "autogroup:member"],
         "attr": ["mullvad"]
       }
     ]
     ```
2. **Alternative (Manual Device Assignment)**:
   - Open **[Tailscale Admin Console -> Mullvad VPN](https://login.tailscale.com/admin/mullvad)** (or **Machines** -> select `fidelacchius-arr-vpn` / `fidelacchius` -> **Edit route settings**).
   - Enable the **Mullvad VPN** toggle for `fidelacchius-arr-vpn` (and optionally `fidelacchius` if you want to run `tailscale exit-node list` from the host CLI to browse available Mullvad exit nodes).

### Step 1.2: Generate a Tailscale Auth Key & Choose an Exit Node

1. Open **[Tailscale Admin Console -> Settings -> Keys](https://login.tailscale.com/admin/settings/keys)**.
2. Click **Generate auth key...**:
   - **Reusable**: Enabled (recommended so container recreations stay seamless, though state is also persisted in `/opt/services/arr/vpn/config`).
   - **Tags**: `tag:arr-vpn` (if using the ACL snippet above).
   - Copy the generated `tskey-auth-...` key.
3. Discover available Mullvad exit nodes (from any machine granted the `mullvad` attribute):
   ```bash
   tailscale exit-node list
   # Example Mullvad exit node hostname: us-nyc-wg-301.mullvad.ts.net (or its 100.x.y.z IP)
   ```

### Step 1.3: Populate `ansible/inventory/group_vars/all/vault.yml`

Add your Tailscale auth key and chosen exit node to `ansible/inventory/group_vars/all/vault.yml` (gitignored; see `vault.yml.example` for reference):

```yaml
# ansible/inventory/group_vars/all/vault.yml (gitignored)
vault_arr_tailscale_auth_key: "tskey-auth-kXXXXXX-XXXXXXXXXXXXXXXXXXXX"
vault_arr_tailscale_exit_node: "us-nyc-wg-301.mullvad.ts.net"
```

*(Note: If you ever switch `arr_vpn_mode: "gluetun"` in `vars.yml` to use raw standalone WireGuard keys outside Tailscale, populate `vault_arr_vpn_*` instead.)*

### Step 1.4: Enable Tailscale Subnet Routing on Host `fidelacchius` (For Remote Access to `jellyfin.lan` / `qbittorrent.lan`)

Because `fidelacchius` uses `100.103.39.60:443` for Tailscale Funnel (Vaultwarden), Caddy binds to `127.0.0.1` and `192.168.4.57`. To reach `https://jellyfin.lan` and `https://qbittorrent.lan` (`192.168.4.57`) from remote Tailscale devices (`iphone173`, `mattframework`) when away from home:
```bash
# 1. Advertise the home LAN subnet from fidelacchius:
sudo tailscale set --advertise-routes=192.168.4.0/24

# 2. In Tailscale Admin Console -> Machines -> fidelacchius -> Edit route settings:
#    Approve subnet route 192.168.4.0/24
```

### Step 1.5: Verify Host Hardware & Storage Mounts

```bash
# 1. Verify Docker and Compose v2 are operational
docker --version && docker compose version

# 2. Verify all three storage tiers are mounted (/opt/services, /mnt/storage, /mnt/scratch)
df -h /opt/services /mnt/storage /mnt/scratch
mountpoint /mnt/storage && mountpoint /mnt/scratch

# 3. Verify TUN device and Intel UHD Graphics 770 iGPU render node exist
ls -la /dev/net/tun
ls -la /dev/dri/by-path/pci-0000:00:02.0-render /dev/dri/by-path/pci-0000:00:02.0-card
```

---

## 2. Deployment & Convergence

### Option A: Local Convergence (on host `fidelacchius`)

```bash
cd /home/admin/projects/homelab2

# Execute the Phase 5 Media & Arr Stage 1 convergence runner locally
./scripts/apply-phase5-arr.sh --local
```

### Option B: Remote Operator Convergence (from workstation)

```bash
# Via POSIX Bash runner:
./scripts/apply-phase5-arr.sh --host 192.168.4.57 --user admin

# Or via PowerShell 7+ on Windows:
pwsh ./scripts/apply-phase5-arr.ps1 -Host 192.168.4.57 -User admin
```

### Option C: Direct Ansible Playbook Invocations

```bash
# Check mode (dry run / idempotency verification)
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/arr.yml --check

# Apply convergence
ansible-playbook -i ansible/inventory/hosts.yml ansible/playbooks/arr.yml
```

---

## 3. Automated Acceptance Verification

Run the automated acceptance suite (`scripts/verify-phase5-arr.sh`) to validate all 10 Stage 1 assertions (`ARR-01` through `ARR-10`):

```bash
# Run acceptance assertions locally:
./scripts/verify-phase5-arr.sh --local

# Or with JSON structured output:
./scripts/verify-phase5-arr.sh --local --json

# Expected output:
# [PASS] ARR-01: arr.service active and 3 containers (arr_vpn, arr_qbittorrent, arr_jellyfin) running healthy
# [PASS] ARR-02: arr_vpn Tailscale exit-node tunnel active, external VPN IP differs from host WAN IP, UID 1000 kill-switch active
# [PASS] ARR-03: arr_qbittorrent isolated inside arr_vpn network namespace (container:<arr_vpn_id>)
# [PASS] ARR-04: Jellyfin /health (HTTP 200) and qBittorrent WebUI (HTTP 200) responding on loopback
# [PASS] ARR-05: WebUI ports bound strictly to 127.0.0.1 and Caddy 40-arr.caddy validated
# [PASS] ARR-06: Intel UHD 770 iGPU (00:02.0) bound with LIBVA_DRIVER_NAME=iHD; AMD GPU (03:00.0) isolated
# [PASS] ARR-07: Three-tier storage layout (Stage 1+2 scaffold, scratch, MergerFS) & SnapRAID /downloads/ exclusion verified
# [PASS] ARR-08: Unified ownership (PUID=1000, PGID=1001, UMASK=002, mode 2775) verified across storage tiers
# [PASS] ARR-09: Secret isolation (.env 0600, 0 git leaks) & 40-arr.sh SQLite backup hook verified
# [PASS] ARR-10: Journald and container logs clean with zero fatal panics or credential leaks
# Exit Code: 0 (All 10 assertions passed)
```

---

## 4. Initial Service Onboarding

### 4.1 Jellyfin Media Server Setup
1. Access Jellyfin from a trusted LAN or Tailscale device:
   - Over LAN / Tailscale Subnet Route: `https://jellyfin.lan` (or `http://127.0.0.1:8096` via SSH tunnel)
2. Complete the Jellyfin Startup Wizard:
   - Create the primary administrator account.
   - Add Media Libraries:
     - **Movies**: Folder `/mnt/storage/media/movies`
     - **Shows (TV)**: Folder `/mnt/storage/media/tv`
3. Verify Hardware Acceleration (**Dashboard** -> **Playback** -> **Transcoding**):
   - Set **Hardware acceleration** to `Intel QuickSync (QSV)` or `Video Acceleration API (VAAPI)`.
   - Verify VA-API Device is `/dev/dri/renderD128`.
   - Enable hardware decoding for `H264`, `HEVC`, `MPEG2`, `VP9`, `AV1`, and `HEVC 10bit`.

### 4.2 qBittorrent Download Client Setup
1. Retrieve the initial temporary WebUI password (generated on first startup if not yet customized):
   ```bash
   docker logs arr_qbittorrent 2>&1 | grep -i "temporary password"
   ```
2. Access qBittorrent from a trusted LAN or Tailscale device:
   - Over LAN / Tailscale Subnet Route: `https://qbittorrent.lan`
3. Navigate to **Tools** -> **Options**:
   - **Web UI**: Set a permanent administrator username and strong password (stored hashed in `qBittorrent.conf`), and optionally enable *Bypass authentication for clients on localhost* (`127.0.0.1/32`).
   - **Downloads**:
     - Confirm **Default Save Path**: `/mnt/storage/downloads/complete`
     - Confirm **Keep incomplete torrents in**: `/mnt/scratch/downloads/incomplete`
   - **Advanced** -> **Network interface** (Optional extra belt-and-suspenders): Bind qBittorrent to `tailscale0` (`tun0` if using Gluetun).

---

## 5. Backup & Disaster Recovery Verification

Verify that online SQLite database snapshots and service configurations are staged cleanly for Backblaze B2 without stopping Jellyfin or qBittorrent:

```bash
# 1. Trigger the pre-backup hook manually
sudo /etc/homelab/backup.d/40-arr.sh pre-backup

# 2. Inspect generated SQLite snapshots and config archive
sudo ls -lh /opt/services/arr/backups/

# 3. Verify Restic backup exclusion rules exclude bulk media and downloads
grep -E "(downloads|media/movies|media/tv|arr)" /etc/homelab/backup-excludes.txt
```
