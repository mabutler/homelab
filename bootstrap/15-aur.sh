#!/usr/bin/env bash
# bootstrap/15-aur.sh — the ability to install from the AUR, and nothing else.
#
# This step exists because mergerfs and snapraid are AUR-only. There is no
# version of this design that keeps both and avoids the AUR, so the cost is
# paid here, once, deliberately and in one place:
#
#   * base-devel lands on the host — a compiler on a machine whose package set
#     was chosen to be minimal.
#   * AUR packages do not ride `pacman -Syu`. They also need *rebuilding* when
#     a dependency's soname moves, which is how a routine update breaks a
#     filesystem months after you stopped watching. paru covers both repos and
#     the AUR in one command, which is why it is here rather than bare makepkg
#     — the quarterly ritual becomes `paru -Syu` and nothing gets forgotten.
#
# Idempotent.

# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root
require_installed_system
load_host_conf

id -u "$ADMIN_USER" >/dev/null 2>&1 \
    || die "$ADMIN_USER does not exist — paru and makepkg refuse to run as root"

if command -v paru >/dev/null 2>&1; then
    dbg "paru already installed"
    ok "AUR support present"
    exit 0
fi

# base-devel supplies makepkg, gcc and friends. git fetches the PKGBUILD.
pkg_install base-devel git

log "building paru from the AUR (this is the slow part on a Sandy Bridge i3)"
warn "paru is written in Rust, so this pulls the Rust toolchain to build it."
warn "makepkg -r removes those build-only dependencies afterwards, so the"
warn "host does not keep ~1.5 GB of compiler it will never use again."

if [[ -n "$DRY_RUN" ]]; then
    log "would clone and build paru as $ADMIN_USER"
else
    # A PKGBUILD is arbitrary code, which is exactly why makepkg refuses to run
    # as root. Build as the admin user in a scratch directory they own; the
    # NOPASSWD sudo rule from install/ lets makepkg call pacman to install the
    # result without an interactive prompt.
    build_dir="$(mktemp -d /tmp/aur-paru.XXXXXX)"
    chown "$ADMIN_USER:$ADMIN_USER" "$build_dir"

    sudo -u "$ADMIN_USER" -H \
        git clone --depth 1 https://aur.archlinux.org/paru.git "$build_dir/paru"

    # -s installs makedepends, -i installs the result, -r removes the
    # makedepends again, -c cleans the build tree.
    ( cd "$build_dir/paru" && sudo -u "$ADMIN_USER" -H makepkg -sirc --noconfirm )

    rm -rf -- "$build_dir"
fi

if [[ -z "$DRY_RUN" ]]; then
    command -v paru >/dev/null 2>&1 || die "paru did not install"
    ok "paru $(paru --version 2>/dev/null | head -1)"
fi

cat >&2 <<'EOF'

  Consequence for the quarterly ritual: `pacman -Syu` no longer covers
  everything on this host. Use `paru -Syu` instead — same keyring-first
  caveat, but it rebuilds AUR packages when their dependencies move.

  The AUR packages this host relies on are mergerfs (bootstrap/40) and
  snapraid (bootstrap/50). Both are load-bearing for the pool, so a
  failed rebuild is worth reading the output of rather than skipping.
EOF

ok "AUR support installed"
