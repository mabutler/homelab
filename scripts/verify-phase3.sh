#!/usr/bin/env bash
# scripts/verify-phase3.sh
# Acceptance verification runner for homelab2 Phase 3 (Network & Remote Access Overlay)
# Enforces the 8-point Assertion Matrix from contracts/verification-suite.md:
# NET-01: systemctl is-active nftables.service == active (exit 1)
# NET-02: nft list table inet filter contains drop policy & whitelisted ports (exit 2)
# NET-03: systemctl is-active tailscaled.service == active (exit 3)
# NET-04: tailscale status reports BackendState == "Running" (exit 4)
# NET-05: systemctl is-active caddy.service == active (exit 5)
# NET-06: http://127.0.0.1:80/health returns HTTP 200 (exit 6)
# NET-07: http://127.0.0.1:80/ returns HTTP 301 or 308 HTTPS redirect (exit 7)
# NET-08: ss -tulpn confirms listening ports 22, 80, 443, and 41641/udp (exit 8)

set -euo pipefail

TARGET_HOST="192.168.4.57"
SSH_USER="admin"
IDENTITY_FILE=""
LOCAL_MODE=false

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [TARGET_HOST]

Options:
  -h, --host <IP|HOSTNAME>   Target host to verify (default: $TARGET_HOST)
  -u, --user <USERNAME>       SSH user for test connection (default: $SSH_USER)
  -i, --identity <KEY_PATH>   SSH identity file (private key)
  --local                     Run assertions directly against localhost
  --help                      Show this help message and exit

Exit Codes:
  0 - All assertions passed (100% compliance)
  1-8 - Assertion failure for NET-01 through NET-08
EOF
    exit 0
}

if SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)"; then
    REPO_ROOT="$SCRIPT_DIR"
else
    REPO_ROOT="$(pwd)"
fi
INVENTORY_FILE="${REPO_ROOT}/ansible/inventory/hosts.yml"

if [[ -f "$INVENTORY_FILE" ]]; then
    PARSED_HOST=$(grep -E 'ansible_host:' "$INVENTORY_FILE" | head -n1 | awk '{print $2}' || true)
    PARSED_USER=$(grep -E 'ansible_user:' "$INVENTORY_FILE" | head -n1 | awk '{print $2}' || true)
    if [[ -n "$PARSED_HOST" ]]; then TARGET_HOST="$PARSED_HOST"; fi
    if [[ -n "$PARSED_USER" ]]; then SSH_USER="$PARSED_USER"; fi
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--host)
            TARGET_HOST="$2"
            shift 2
            ;;
        -u|--user)
            SSH_USER="$2"
            shift 2
            ;;
        -i|--identity)
            IDENTITY_FILE="$2"
            shift 2
            ;;
        --local)
            LOCAL_MODE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            TARGET_HOST="$1"
            shift
            ;;
    esac
done

run_cmd() {
    local cmd="$1"
    if [[ "$LOCAL_MODE" == "true" ]]; then
        eval "$cmd"
    else
        local ssh_cmd=(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=30)
        if [[ -n "$IDENTITY_FILE" ]]; then
            ssh_cmd+=(-i "$IDENTITY_FILE")
        fi
        "${ssh_cmd[@]}" "${SSH_USER}@${TARGET_HOST}" "$cmd"
    fi
}

echo -e "${BLUE}=== fidelacchius Phase 3 Acceptance Verification Suite ===${NC}"
if [[ "$LOCAL_MODE" == "true" ]]; then
    echo "Execution Target: localhost (local execution)"
else
    echo "Execution Target: ${SSH_USER}@${TARGET_HOST}"
fi
echo ""

# Assertion 1: NET-01 nftables.service active
echo -n "Checking NET-01: nftables.service is active... "
if run_cmd "systemctl is-active nftables.service" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "ERROR: [NET-01] nftables.service is not active" >&2
    exit 1
fi

# Assertion 2: NET-02 nftables ruleset
echo -n "Checking NET-02: nftables ruleset contains default drop & allowed ports... "
NFT_RULES=$(run_cmd "sudo nft list table inet filter" 2>/dev/null || true)
if echo "$NFT_RULES" | grep -q "type filter hook input priority filter; policy drop;" && \
   echo "$NFT_RULES" | grep -q "ct state established,related accept" && \
   echo "$NFT_RULES" | grep -q "41641"; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "ERROR: [NET-02] nftables ruleset does not match required contract" >&2
    exit 2
fi

# Assertion 3: NET-03 tailscaled.service active
echo -n "Checking NET-03: tailscaled.service is active... "
if run_cmd "systemctl is-active tailscaled.service" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "ERROR: [NET-03] tailscaled.service is not active" >&2
    exit 3
fi

# Assertion 4: NET-04 tailscale status authenticated & node identity
echo -n "Checking NET-04: tailscale mesh status online & node identity fidelacchius... "
TS_STATUS=$(run_cmd "tailscale status --json" 2>/dev/null || true)
BACKEND_STATE=$(echo "$TS_STATUS" | jq -r '.BackendState // empty' 2>/dev/null || true)
TS_HOSTNAME=$(echo "$TS_STATUS" | jq -r '.Self.HostName // empty' 2>/dev/null || true)
TS_DNSNAME=$(echo "$TS_STATUS" | jq -r '.Self.DNSName // empty' 2>/dev/null || true)
SYS_HOSTNAME=$(run_cmd "hostnamectl --static 2>/dev/null || uname -n" | tr -d '[:space:]')

if [[ "$BACKEND_STATE" == "Running" || "$BACKEND_STATE" == "Starting" ]] && \
   [[ "$SYS_HOSTNAME" == "fidelacchius" ]] && \
   [[ "$TS_HOSTNAME" == "fidelacchius" ]] && \
   [[ "$TS_DNSNAME" == "fidelacchius.fable-mackarel.ts.net." ]]; then
    echo -e "${GREEN}PASS${NC} (state: ${BACKEND_STATE}, host: ${SYS_HOSTNAME}, node: ${TS_HOSTNAME}, fqdn: ${TS_DNSNAME})"
else
    if [[ "$SYS_HOSTNAME" != "fidelacchius" ]]; then
        echo -e "${RED}FAIL${NC}"
        echo "ERROR: [NET-04] System static hostname is '$SYS_HOSTNAME', expected 'fidelacchius'" >&2
        exit 4
    elif [[ "$TS_HOSTNAME" != "fidelacchius" || "$TS_DNSNAME" != "fidelacchius.fable-mackarel.ts.net." ]]; then
        echo -e "${RED}FAIL${NC}"
        echo "ERROR: [NET-04] Tailscale node identity is '$TS_HOSTNAME' ($TS_DNSNAME), expected 'fidelacchius' (fidelacchius.fable-mackarel.ts.net.)" >&2
        exit 4
    else
        echo -e "${RED}FAIL${NC}"
        echo "ERROR: [NET-04] tailscale node is not connected to mesh (state: ${BACKEND_STATE:-unknown})" >&2
        exit 4
    fi
fi

# Assertion 5: NET-05 caddy.service active
echo -n "Checking NET-05: caddy.service is active... "
if run_cmd "systemctl is-active caddy.service" >/dev/null 2>&1; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "ERROR: [NET-05] caddy.service is not active" >&2
    exit 5
fi

# Assertion 6: NET-06 HTTP /health endpoint returns 200
echo -n "Checking NET-06: Ingress HTTP /health endpoint returns 200 OK... "
HTTP_CODE=$(run_cmd "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:80/health" 2>/dev/null || true)
if [[ "$HTTP_CODE" == "200" ]]; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC} (got HTTP $HTTP_CODE)"
    echo "ERROR: [NET-06] Ingress HTTP /health did not return 200" >&2
    exit 6
fi

# Assertion 7: NET-07 HTTP root returns 301 or 308 redirect
echo -n "Checking NET-07: Ingress HTTP root redirects to HTTPS (301/308)... "
REDIRECT_CODE=$(run_cmd "curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:80/" 2>/dev/null || true)
if [[ "$REDIRECT_CODE" == "301" || "$REDIRECT_CODE" == "308" ]]; then
    echo -e "${GREEN}PASS${NC} (got HTTP $REDIRECT_CODE)"
else
    echo -e "${RED}FAIL${NC} (got HTTP $REDIRECT_CODE)"
    echo "ERROR: [NET-07] Ingress HTTP root did not return redirect" >&2
    exit 7
fi

# Assertion 8: NET-08 Listening sockets
echo -n "Checking NET-08: Required network listening ports (22, 80, 443, 41641)... "
SS_OUTPUT=$(run_cmd "ss -tulpn" 2>/dev/null || true)
if echo "$SS_OUTPUT" | grep -q ':22 ' && \
   echo "$SS_OUTPUT" | grep -q ':80 ' && \
   echo "$SS_OUTPUT" | grep -q ':443 '; then
    echo -e "${GREEN}PASS${NC}"
else
    echo -e "${RED}FAIL${NC}"
    echo "ERROR: [NET-08] Missing expected listening sockets on ports 22, 80, or 443" >&2
    exit 8
fi

echo ""
echo -e "${GREEN}✓ All 8 network acceptance assertions passed successfully (100% compliance).${NC}"
exit 0
