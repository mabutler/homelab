# Contract: Network Exposure & Firewall Isolation (`FRIGATE-NETWORK-V1`)

**Feature**: `009-frigate-nvr-setup`  
**Date**: 2026-11-04  
**Requirements Covered**: FR-010, SC-001, Constitution Operational Standards

---

## 1. Exposed Service Endpoints

| Port | Protocol | Service Component | Allowed Sources | Public Internet / Funnel |
|---|---|---|---|---|
| `5000` | TCP | Frigate Web UI & HTTP API (`/api/version`, `/api/stats`, `/api/config`) | `lo` (`127.0.0.1`), LAN (`192.168.4.0/24`), Tailscale (`tailscale0`) | **DENIED / NOT EXPOSED** |
| `8971` | TCP | Frigate Authenticated HTTPS UI | `lo` (`127.0.0.1`), LAN (`192.168.4.0/24`), Tailscale (`tailscale0`) | **DENIED / NOT EXPOSED** |
| `8554` | TCP | go2rtc RTSP Restream | `lo` (`127.0.0.1`), LAN (`192.168.4.0/24`), Tailscale (`tailscale0`) | **DENIED / NOT EXPOSED** |
| `8555` | TCP & UDP | go2rtc WebRTC Live View | `lo` (`127.0.0.1`), LAN (`192.168.4.0/24`), Tailscale (`tailscale0`) | **DENIED / NOT EXPOSED** |

---

## 2. Firewall Enforcement (`nftables` `/etc/nftables.conf`)

1. **Loopback (`lo`)**: Unconditionally accepted (`iifname "lo" accept`).
2. **Tailscale VPN Overlay (`tailscale0`)**: Unconditionally accepted for authenticated tailnet members (`iifname "tailscale0" accept`).
3. **Trusted Local LAN (`192.168.4.0/24`)**:
   - Explicitly allowed to reach Frigate TCP ports `{ 5000, 8971, 8554, 8555 }` and UDP port `{ 8555 }` from `firewall_allowed_subnets` (`192.168.4.0/24`).
4. **Public / Untrusted Networks**:
   - Dropped by default chain policy (`policy drop;`).
   - Tailscale Funnel (`tailscale funnel status`) MUST NOT proxy to port `5000`, `8971`, `8554`, or `8555`.

---

## 3. API Health Probe Specification

| Endpoint | Method | Expected HTTP Status | Expected Payload / Condition | Latency SLA |
|---|---|---|---|---|
| `http://127.0.0.1:5000/api/version` | `GET` | `200 OK` | Semantic version string matching `0.14.1` | `< 2000 ms` (SC-001) |
| `http://127.0.0.1:5000/api/stats` | `GET` | `200 OK` | JSON containing `detectors.ov` and `service.uptime` | `< 2000 ms` (SC-001) |
| `http://127.0.0.1:5000/api/config` | `GET` | `200 OK` | JSON containing `cameras.camera_1` and `cameras.camera_2` | `< 2000 ms` |
