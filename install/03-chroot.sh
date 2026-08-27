#!/usr/bin/env bash
# install/03-chroot.sh — configure the installed system so it boots, and so
# you can get back into it without a keyboard.
#
# Does NOT reboot. It prints the next command and exits, because the assertions
# at the end are the whole point: this is the last moment at which a mistake is
# cheap. After the reboot, a broken sshd or a missing key means walking to the
# machine with a monitor.
#
# install/ runs once, but this script is written to be safely re-runnable from
# the top: it is long, it can stop partway, and the way you recover from that
# should be running it again rather than working out which half already
# happened. Every step here is either a no-op when already done or harmless
# to repeat.

# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root
require_live_iso
require_cmd arch-chroot findmnt
load_host_conf
load_drives_conf

TARGET_MNT="${TARGET_MNT:-/mnt}"
export INSTALL_ROOT="$TARGET_MNT"

findmnt -M "$TARGET_MNT" >/dev/null || die "$TARGET_MNT is not mounted"
[[ -x "$TARGET_MNT/usr/bin/pacman" ]] \
    || die "$TARGET_MNT has no base system — run install/02-pacstrap.sh first"

ssd_serial="$(serials_with_role ssd)"
ssd_dev="$(resolve_serial "$ssd_serial")"

# chr <cmd>... — run inside the target.
chr() { arch-chroot "$TARGET_MNT" "$@"; }

# link_in_target <target> <linkpath> — create a symlink in the target.
#
# Deliberately NOT run through chr(). arch-chroot bind-mounts the host's
# /etc/resolv.conf into the target for the duration of every call, so anything
# chr() does to that path acts on the live ISO's file: `rm` fails with "device
# or resource busy", and `ln -sf` refuses with "are the same file" because both
# paths reach one inode through the bind mount.
#
# From outside there is no such mount between calls, and a symlink written here
# is byte-identical to one written inside. The link text is interpreted from
# within the target when the machine boots, so an absolute target like
# /usr/share/zoneinfo/... is correct even though it points somewhere else on
# the ISO.
link_in_target() {
    local target="$1" link="$2"
    local path="$TARGET_MNT$link" current

    if mountpoint -q -- "$path" 2>/dev/null; then
        die "$path is a mount point — a leaked arch-chroot bind mount. umount it and re-run."
    fi

    current="$(readlink -- "$path" 2>/dev/null || true)"
    if [[ "$current" == "$target" ]]; then
        dbg "$link already -> $target"
        return 0
    fi

    log "link $link -> $target${current:+  (was: $current)}"
    rm -f -- "$path"
    ln -sT -- "$target" "$path"
}

# --- locale, time, identity ------------------------------------------------
install_template etc/locale.gen
install_template etc/locale.conf
install_template etc/vconsole.conf
install_template etc/hostname
install_template etc/hosts

log "generating locale $LOCALE"
chr locale-gen

log "timezone $TIMEZONE"
link_in_target "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
chr hwclock --systohc

# --- the admin account -----------------------------------------------------
# Root's password is left unset, which leaves the account locked. sshd refuses
# root anyway, and recovery is the live ISO or a snapper rollback from the GRUB
# menu — both of which you have. A root password that exists is one more thing
# to store and one more way in.
#
# With root locked and wheel set to NOPASSWD, this user's password is the only
# credential for a console login at the machine itself. That is the way back in
# when sshd and Tailscale are both unavailable, so it is set below and checked
# rather than left optional.
if chr id -u "$ADMIN_USER" >/dev/null 2>&1; then
    dbg "user $ADMIN_USER already exists"
else
    log "creating $ADMIN_USER"
    chr useradd -m -G wheel -s /bin/bash "$ADMIN_USER"
fi

install_file etc/sudoers.d/10-wheel 0440

log "installing SSH key for $ADMIN_USER"
chr install -d -m 0700 -o "$ADMIN_USER" -g "$ADMIN_USER" "/home/$ADMIN_USER/.ssh"
install -Dm600 -- "$FILES_DIR/authorized_keys" \
    "$TARGET_MNT/home/$ADMIN_USER/.ssh/authorized_keys"
chr chown "$ADMIN_USER:$ADMIN_USER" "/home/$ADMIN_USER/.ssh/authorized_keys"

# --- access ----------------------------------------------------------------
install_file etc/ssh/sshd_config.d/10-hardening.conf
install_file etc/systemd/network/20-wired.network

grep -q '^Include /etc/ssh/sshd_config.d/\*\.conf' "$TARGET_MNT/etc/ssh/sshd_config" \
    || die "the target's sshd_config does not Include sshd_config.d — the hardening drop-in would be ignored"

# A fresh pacstrap has no host keys; Arch generates them at first boot via
# sshdgenkeys.service. Doing it now instead means `sshd -t` below is actually
# able to validate the config — without keys it exits before parsing anything —
# and the host is reachable the moment sshd starts rather than after keygen.
# ssh-keygen -A only creates what is missing, so this is safe to repeat.
log "generating SSH host keys"
chr ssh-keygen -A

chr systemctl enable sshd.service
chr systemctl enable systemd-networkd.service
chr systemctl enable systemd-resolved.service
link_in_target ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# --- boot ------------------------------------------------------------------
log "mkinitcpio for all kernels"
chr mkinitcpio -P

install_file etc/default/grub

if [[ -d /sys/firmware/efi ]]; then
    chr grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Arch
else
    log "grub-install (i386-pc) to $ssd_dev"
    chr grub-install --target=i386-pc "$ssd_dev"
fi
chr grub-mkconfig -o /boot/grub/grub.cfg

# --- the repository --------------------------------------------------------
# Copied, not cloned. host.conf is gitignored, so a clone would silently leave
# the machine's identity behind and run.sh would fail after the reboot.
log "copying the repository to /opt/stack"
mkdir -p "$TARGET_MNT/opt/stack"
cp -a "$REPO_ROOT/." "$TARGET_MNT/opt/stack/"
chr chown -R root:root /opt/stack

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------
# Everything above this line can fail quietly and still look like it worked.
# Each check below is one way the machine could come back unreachable.
log "verifying the target can boot and be reached"

AUTHKEYS="$TARGET_MNT/home/$ADMIN_USER/.ssh/authorized_keys"
GRUBCFG="$TARGET_MNT/boot/grub/grub.cfg"

fail=0
check() {
    local desc="$1"
    shift
    if "$@"; then
        ok "$desc"
    else
        err "FAILED: $desc"
        fail=$(( fail + 1 ))
    fi
}

# Small named predicates rather than quoted strings fed to eval: these are the
# checks standing between you and a machine that needs a monitor, so they
# should be readable at a glance.
c_sshd_parses()   { chr sshd -t; }
c_sudoers()       { chr visudo -cf /etc/sudoers.d/10-wheel >/dev/null; }
c_user_exists()   { chr id -u "$ADMIN_USER" >/dev/null 2>&1; }
c_in_wheel()      { chr id -nG "$ADMIN_USER" | grep -qw wheel; }
c_login_shell()   { chr getent passwd "$ADMIN_USER" | grep -qvE ':(/usr/bin/nologin|/bin/false)$'; }
# stat has to run inside the target: the ISO has no passwd entry for the admin
# user, so %U there reports UNKNOWN no matter how correct the ownership is.
c_key_perms()     { [[ "$(chr stat -c '%a %U' "/home/$ADMIN_USER/.ssh/authorized_keys")" == "600 $ADMIN_USER" ]]; }
c_ssh_dir()       { [[ "$(chr stat -c '%a %U' "/home/$ADMIN_USER/.ssh")" == "700 $ADMIN_USER" ]]; }
c_hostkeys()      { chr sh -c 'ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1'; }
c_key_present()   { grep -q '^ssh-' "$AUTHKEYS"; }
c_sshd_enabled()  { chr systemctl is-enabled sshd.service >/dev/null; }
c_netd_enabled()  { chr systemctl is-enabled systemd-networkd.service >/dev/null; }
c_network_file()  { [[ -f "$TARGET_MNT/etc/systemd/network/20-wired.network" ]]; }
# arch-chroot leaves an empty regular file here if it ever had to create one,
# and systemd's tmpfiles rule will not replace an existing file — that boots to
# no DNS at all.
c_resolv_link()   { [[ "$(readlink "$TARGET_MNT/etc/resolv.conf")" == ../run/systemd/resolve/stub-resolv.conf ]]; }
c_fstab_labels()  { ! grep -qE '^/dev/(sd|nvme|hd)' "$TARGET_MNT/etc/fstab"; }
c_grubcfg()       { [[ -s "$GRUBCFG" ]]; }
# Fixed-string, and with the closing quote of the menuentry title included:
# "linux-lts" would otherwise satisfy a search for "linux" and the fallback
# entry would look present when only the LTS one had been generated.
c_lts_entry()     { grep -qF "Arch Linux, with Linux linux-lts'" "$GRUBCFG"; }
c_fallback()      { grep -qF "Arch Linux, with Linux linux'" "$GRUBCFG"; }
c_submenu()       { grep -qF 'Advanced options for Arch Linux' "$GRUBCFG"; }
c_hostconf()      { [[ -f "$TARGET_MNT/opt/stack/host.conf" ]]; }
c_git()           { [[ -d "$TARGET_MNT/opt/stack/.git" ]]; }

check "sshd config parses"                     c_sshd_parses
check "sudoers drop-in parses"                 c_sudoers
check "$ADMIN_USER exists"                     c_user_exists
check "$ADMIN_USER is in wheel"                c_in_wheel
check "$ADMIN_USER has a login shell"          c_login_shell
check "authorized_keys is 0600, owned by $ADMIN_USER" c_key_perms
check "authorized_keys holds a public key"     c_key_present
check ".ssh is 0700, owned by $ADMIN_USER"     c_ssh_dir
check "host keys exist"                        c_hostkeys
check "sshd is enabled"                        c_sshd_enabled
check "systemd-networkd is enabled"            c_netd_enabled
check "a .network file is present"             c_network_file
check "resolv.conf points at the resolved stub" c_resolv_link
check "fstab uses labels, not device paths"    c_fstab_labels
check "grub.cfg was generated"                 c_grubcfg
check "LTS boot entry exists"                  c_lts_entry
check "mainline fallback entry exists"         c_fallback
check "advanced submenu exists (GRUB_DEFAULT needs it)" c_submenu
check "host.conf reached /opt/stack"           c_hostconf
check "/opt/stack is a git checkout"           c_git

(( fail == 0 )) || die "$fail check(s) failed — fix them before rebooting, or you will need a monitor"

# --- the password ----------------------------------------------------------
# Last, so a failed assertion above does not waste the prompt. Interactive on
# purpose: nothing about this belongs in host.conf or in the repository.
printf '\n' >&2
log "set the password for $ADMIN_USER"
warn "this is not for sudo (NOPASSWD) or SSH (key-only) — it is the only"
warn "credential for a console login at the machine, with root locked"
until chr passwd "$ADMIN_USER"; do
    warn "passwd failed — try again"
done

# `passwd -S` prints "<user> <state> <date> …". "P" means a usable password is
# set; "L" is locked and "NP" is none, and without one there is no way into the
# machine at a keyboard. Parsed with parameter expansion rather than awk, to
# keep a nested-quoting hazard out of a line that only ever runs once.
pwline="$(chr passwd -S "$ADMIN_USER")"
pwstate="${pwline#* }"      # drop the username
pwstate="${pwstate%% *}"    # keep the state field
[[ "$pwstate" == "P" ]] \
    || die "$ADMIN_USER has no usable password (state: $pwstate) — console recovery would be impossible"
ok "console login for $ADMIN_USER is set"

cat >&2 <<EOF

  ──────────────────────────────────────────────────────
  Ready to reboot. Nothing here reboots for you.

    1. umount -R $TARGET_MNT
    2. reboot, and pull the USB stick
    3. ssh $ADMIN_USER@<address>          # key-only
    4. cd /opt/stack && sudo ./run.sh

  If step 3 fails you will need a monitor and keyboard,
  which is what every check above was for.
  ──────────────────────────────────────────────────────
EOF
