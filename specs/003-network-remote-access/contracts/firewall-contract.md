# Contract: Host-Level Firewall (`nftables`) Specification

**Feature**: `003-network-remote-access`  
**Contract ID**: `CNTR-NET-002`  
**Status**: Ratified  

---

## 1. Specification & Layout

The host packet filter is defined in `/etc/nftables.conf` as a single, dual-stack `inet` family table.

---

## 2. Configuration Schema (`/etc/nftables.conf`)

```nftables
#!/usr/bin/nft -f

# Flush existing rules on reload
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;

        # 1. Allow established and related traffic
        ct state established,related accept

        # 2. Drop invalid packets
        ct state invalid drop

        # 3. Allow loopback traffic
        iifname "lo" accept

        # 4. Allow ICMP / ICMPv6 (diagnostics and path MTU discovery)
        ip protocol icmp accept
        ip6 nexthdr ipv6-icmp accept

        # 5. Allow Tailscale mesh interface traffic unconditionally
        iifname "tailscale0" accept

        # 6. Allow Tailscale UDP encapsulation port on physical interfaces
        udp dport 41641 accept

        # 7. Allow SSH (TCP 22) from local management subnet
        ip saddr 192.168.4.0/24 tcp dport 22 accept

        # 8. Allow Web Ingress (HTTP 80 and HTTPS 443) on all interfaces
        tcp dport { 80, 443 } accept

        # Default policy is drop; unmatched packets are discarded
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }
}
```

---

## 3. Operational Guarantees & Safety Verification

1. **Syntax Validation Before Apply**:
   - The configuration file MUST pass syntax validation via `nft -c -f /etc/nftables.conf` prior to service start or reload.
   - If syntax verification exits with non-zero code, deployment terminates and leaves existing active kernel rules unchanged.
2. **Lockout Protection**:
   - Loopback and established/related connections are permitted before any port drops.
   - Local subnet `192.168.4.0/24` retains SSH access regardless of mesh status.
3. **Dual-Stack Coverage**:
   - Both IPv4 and IPv6 traffic are governed by the `inet` table with identical drop policies.
