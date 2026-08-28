#!/usr/bin/env bash
# tools/verify.sh — the acceptance checklist, expressed as assertions.
#
# Read-only. Run it any time: after the first reboot, after each bootstrap
# step, and after a quarterly update to confirm nothing drifted.
#
# Three outcomes, not two. A check belonging to a bootstrap stage you have not
# run yet reports as "--" (pending), because a checklist that cries FAIL for
# work you have not done yet is a checklist you stop reading. Exit status is 0
# unless something that *should* be true isn't.
#
# Needs root: sshd -T, blkid and snapraid all read things a normal user cannot.

# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

require_root
require_installed_system
load_host_conf
load_drives_conf

have() { command -v -- "$1" >/dev/null 2>&1; }

# root_source — the device behind /, with any btrfs subvolume suffix removed.
root_source() {
    local src
    src="$(findmnt -no SOURCE /)"
    printf '%s\n' "${src%%\[*}"
}

# ===========================================================================
section "Base system — install/"
# ===========================================================================

c_lts_running()  { [[ "$(uname -r)" == *-lts ]]; }
c_lts_pkg()      { pacman -Q linux-lts; }
c_mainline_pkg() { pacman -Q linux; }
c_lts_entry()    { grep -qF "Arch Linux, with Linux linux-lts'" /boot/grub/grub.cfg; }
c_fallback()     { grep -qF "Arch Linux, with Linux linux'" /boot/grub/grub.cfg; }
c_ucode()        { pacman -Q intel-ucode; }
c_ucode_loaded() { grep -qF 'intel-ucode.img' /boot/grub/grub.cfg; }
# A pacman -Syu that includes a kernel replaces the module tree on disk while
# the old kernel keeps running. Anything that needs to load a module it has not
# already loaded then fails — tailscaled cannot get /dev/net/tun, for instance —
# and it looks like a broken daemon rather than a pending reboot. Testing for
# the directory tests the actual failure condition, not a version string.
c_modules_present() { [[ -d "/usr/lib/modules/$(uname -r)" ]]; }

check "running the LTS kernel ($(uname -r))"        c_lts_running
check "linux-lts installed"                         c_lts_pkg
check "mainline linux installed as a fallback"      c_mainline_pkg
check "LTS entry present in grub.cfg"               c_lts_entry
check "mainline fallback entry present in grub.cfg" c_fallback
check "intel-ucode installed"                       c_ucode
check "microcode is loaded by GRUB"                 c_ucode_loaded

section "Filesystems"

c_root_btrfs()   { [[ "$(findmnt -no FSTYPE /)" == btrfs ]]; }
c_root_label()   { [[ "$(blkid -s LABEL -o value "$(root_source)")" == archroot ]]; }
c_root_subvol()  { [[ "$(findmnt -no OPTIONS /)" == *subvol=/@* ]]; }
c_root_opts()    { local o; o="$(findmnt -no OPTIONS /)"; [[ "$o" == *noatime* && "$o" == *compress=zstd:3* ]]; }
c_appdata_mnt()  { findmnt -no TARGET /opt/appdata; }
c_appdata_fs()   { [[ "$(findmnt -no FSTYPE /opt/appdata)" == ext4 ]]; }
c_appdata_label(){ [[ "$(blkid -s LABEL -o value "$(findmnt -no SOURCE /opt/appdata)")" == APPDATA ]]; }
c_fstab_labels() { ! grep -qE '^/dev/(sd|nvme|hd)' /etc/fstab; }
subvol_mounted() { [[ "$(findmnt -no OPTIONS "$1")" == *"subvol=/$2"* ]]; }
c_home()         { subvol_mounted /home @home; }
c_varlog()       { subvol_mounted /var/log @var_log; }
c_containers()   { subvol_mounted /var/lib/containers @containers; }
c_snapshots()    { subvol_mounted /.snapshots @snapshots; }

check "/ is btrfs"                                  c_root_btrfs
check "/ is on label archroot"                      c_root_label
check "/ is the @ subvolume"                        c_root_subvol
check "/ mounted noatime,compress=zstd:3"           c_root_opts
check "/home is @home"                              c_home
check "/var/log is @var_log"                        c_varlog
check "/var/lib/containers is @containers"          c_containers
check "/.snapshots is @snapshots"                   c_snapshots
check "/opt/appdata is mounted"                     c_appdata_mnt
check "/opt/appdata is ext4"                        c_appdata_fs
check "/opt/appdata is on label APPDATA"            c_appdata_label
check "fstab uses labels, not device paths"         c_fstab_labels

section "Drives"

# Called directly rather than through check(): report_drives prints a table
# worth seeing, and check() swallows output by design.
if report_drives; then
    CHECKS_PASSED=$(( CHECKS_PASSED + 1 ))
else
    CHECKS_FAILED=$(( CHECKS_FAILED + 1 ))
fi

section "Access"

c_sshd_active()  { systemctl is-active --quiet sshd.service; }
# Value anchored so a permissive setting (yes, prohibit-password) still fails.
# grep_output rather than a pipe — see its comment in lib/common.sh.
c_no_passwords() { grep_output '^passwordauthentication[[:space:]]+no$'  sshd -T; }
c_no_root_ssh()  { grep_output '^permitrootlogin[[:space:]]+no$'         sshd -T; }
c_pubkey_on()    { grep_output '^pubkeyauthentication[[:space:]]+yes$'   sshd -T; }
c_hostkeys()     { ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; }
c_key_perms()    { [[ "$(stat -c '%a %U' "/home/$ADMIN_USER/.ssh/authorized_keys")" == "600 $ADMIN_USER" ]]; }
c_ssh_dir()      { [[ "$(stat -c '%a %U' "/home/$ADMIN_USER/.ssh")" == "700 $ADMIN_USER" ]]; }
c_in_wheel()     { [[ " $(id -nG "$ADMIN_USER") " == *" wheel "* ]]; }
c_sudo_nopass()  { grep_output 'NOPASSWD' sudo -n -l -U "$ADMIN_USER"; }
c_root_locked()  { local st; st="$(passwd -S root)"; st="${st#* }"; [[ "${st%% *}" == "L" ]]; }
c_networkd()     { systemctl is-active --quiet systemd-networkd.service; }
c_resolved()     { systemctl is-active --quiet systemd-resolved.service; }
c_dns()          { getent hosts archlinux.org; }

check "sshd is running"                             c_sshd_active
check "password authentication is off"              c_no_passwords
check "root login over ssh is off"                  c_no_root_ssh
check "host keys exist"                             c_hostkeys
check "authorized_keys is 0600, owned by $ADMIN_USER" c_key_perms
check ".ssh is 0700, owned by $ADMIN_USER"          c_ssh_dir
check "$ADMIN_USER is in wheel"                     c_in_wheel
check "wheel has NOPASSWD sudo"                     c_sudo_nopass
check "root account is locked"                      c_root_locked
check "systemd-networkd is running"                 c_networkd
check "systemd-resolved is running"                 c_resolved
check "DNS resolves"                                c_dns

section "Identity"

c_hostname() { [[ "$(hostnamectl --static)" == "$TARGET_HOSTNAME" ]]; }
c_timezone() { [[ "$(timedatectl show -p Timezone --value)" == "$TIMEZONE" ]]; }
c_locale()   { [[ "$(localectl status)" == *"$LOCALE"* ]]; }

check "hostname is $TARGET_HOSTNAME"                c_hostname
check "timezone is $TIMEZONE"                       c_timezone
check "locale is $LOCALE"                           c_locale

section "Repository"

c_stack_git()  { [[ -d /opt/stack/.git ]]; }
c_stack_conf() { [[ -f /opt/stack/host.conf ]]; }
c_stack_clean(){ git -C /opt/stack diff --quiet; }

check "/opt/stack is a git checkout"                c_stack_git
check "/opt/stack has host.conf"                    c_stack_conf
check "/opt/stack has no uncommitted changes"       c_stack_clean

# ===========================================================================
# Everything below belongs to a bootstrap stage. Each section runs its checks
# once that stage has been applied, and reports pending until then.
# ===========================================================================

section "Base tuning — bootstrap/10-base.sh"
if have zramctl && [[ -f /etc/systemd/zram-generator.conf ]]; then
    c_zram()      { grep_output 'zram' swapon --show=NAME --noheadings; }
    c_swappiness(){ [[ "$(sysctl -n vm.swappiness)" == 100 ]]; }
    c_journal()   { grep -qs '^SystemMaxUse=' /etc/systemd/journald.conf /etc/systemd/journald.conf.d/*.conf; }
    c_fstrim()    { systemctl is-enabled --quiet fstrim.timer; }
    # Arch does not enable time sync by default and install/ does not either,
    # so this lives here rather than in the base section — where it would
    # report a failure with nothing to act on.
    c_timesync()  { systemctl is-active --quiet systemd-timesyncd.service; }
    c_ntp()       { [[ "$(timedatectl show -p NTPSynchronized --value)" == yes ]]; }
    check "zram swap is active"                     c_zram
    check "vm.swappiness is 100"                    c_swappiness
    check "journald has a size cap"                 c_journal
    check "fstrim.timer is enabled"                 c_fstrim
    check "systemd-timesyncd is running"            c_timesync
    check "clock is NTP-synchronised"               c_ntp
else
    pending "not run yet — zram, sysctl, journald cap, fstrim, time sync"
fi

section "AUR support — bootstrap/15-aur.sh"
if command -v paru >/dev/null 2>&1; then
    c_paru()      { command -v paru >/dev/null; }
    c_makepkg()   { command -v makepkg >/dev/null; }
    check "paru is installed"                       c_paru
    check "makepkg is available"                    c_makepkg
else
    pending "not run yet — paru, base-devel"
fi

section "Snapshots — bootstrap/20-snapshots.sh"
if have snapper; then
    c_snapper_root(){ grep_output '(^|[[:space:]])root([[:space:]]|$)' snapper list-configs; }
    c_snap_pac()    { pacman -Q snap-pac; }
    # is-active, not is-enabled: grub-btrfsd exits 1 on startup when
    # inotify-tools is absent, and an enabled-but-dead daemon regenerates
    # nothing while looking perfectly configured.
    c_grub_btrfs()  { systemctl is-active --quiet grub-btrfsd.service; }
    c_inotify()     { command -v inotifywait >/dev/null; }
    check "snapper has a config for root"           c_snapper_root
    check "snap-pac is installed"                   c_snap_pac
    check "inotify-tools is installed"              c_inotify
    check "grub-btrfsd is running"                  c_grub_btrfs
else
    pending "not run yet — snapper, snap-pac, grub-btrfs"
fi

section "Tailscale — bootstrap/30-access.sh"
if have tailscale; then
    c_ts_active(){ systemctl is-active --quiet tailscaled.service; }
    c_ts_up()    { tailscale status >/dev/null 2>&1; }
    # A tailnet address in 100.64.0.0/10 is the concrete evidence that the node
    # actually joined, rather than merely having the daemon running.
    c_ts_ip()    { grep_output '^100\.' tailscale ip -4; }
    check "tailscaled is running"                   c_ts_active
    check "the tailnet is up"                       c_ts_up
    check "the node has a tailnet address"          c_ts_ip
else
    pending "not run yet — tailscale"
fi

section "Storage pool — bootstrap/40-storage.sh"
if findmnt -no TARGET /mnt/pool >/dev/null 2>&1; then
    c_pool_fs()    { [[ "$(findmnt -no FSTYPE /mnt/pool)" == fuse.mergerfs ]]; }
    c_fstab_block(){ grep -qF 'homelab pool mounts' /etc/fstab; }
    # Both markers or neither. One without the other means the next run of
    # 40-storage.sh would eat everything after the begin marker.
    c_markers_ok() {
        local b=0 e=0
        grep -qF '>>> homelab pool mounts' /etc/fstab && b=1
        grep -qF '<<< homelab pool mounts' /etc/fstab && e=1
        (( b == e ))
    }
    check "/mnt/pool is mergerfs"                   c_pool_fs
    check "fstab has the managed pool block"        c_fstab_block
    check "the managed block's markers are intact"  c_markers_ok
    for _s in "${DRIVE_SERIALS[@]}"; do
        [[ "${DRIVE_ROLE[$_s]}" == ssd ]] && continue
        _lbl="${DRIVE_LABEL[$_s]}"
        _mnt="$(findmnt -no TARGET "LABEL=$_lbl" 2>/dev/null || true)"
        check "$_lbl is mounted${_mnt:+ at $_mnt}" test -n "$_mnt"
    done
else
    pending "not run yet — mergerfs pool, branch lockdown"
fi

section "SnapRAID — bootstrap/50-snapraid.sh"
if have snapraid && [[ -f /etc/snapraid.conf ]]; then
    c_sr_status(){ snapraid status; }
    c_sr_sync()  { systemctl is-enabled --quiet snapraid-sync.timer; }
    c_sr_scrub() { systemctl is-enabled --quiet snapraid-scrub.timer; }
    check "snapraid status is clean"                c_sr_status
    check "snapraid-sync.timer is enabled"          c_sr_sync
    check "snapraid-scrub.timer is enabled"         c_sr_scrub
else
    pending "not run yet — snapraid config and timers"
fi

section "Alerting — bootstrap/60-alerting.sh"
if have smartd || [[ -x /usr/local/bin/ntfy-alert ]]; then
    c_smartd()     { systemctl is-active --quiet smartd.service; }
    c_smart_state(){ grep -qs '^\s*-s\s' /etc/smartd.conf && grep -qs 'state' /etc/smartd.conf; }
    c_ntfy()       { [[ -x /usr/local/bin/ntfy-alert ]]; }
    c_heartbeat()  { systemctl is-enabled --quiet heartbeat.timer; }
    check "smartd is running"                       c_smartd
    check "smartd keeps persistent state files"     c_smart_state
    check "the ntfy helper is installed"            c_ntfy
    check "the heartbeat timer is enabled"          c_heartbeat
else
    pending "not run yet — smartd, ntfy, heartbeat"
fi

section "Podman — bootstrap/70-podman.sh"
if have podman; then
    c_pod_socket(){ systemctl is-enabled --quiet podman.socket; }
    c_pod_update(){ systemctl is-enabled --quiet podman-auto-update.timer; }
    check "podman.socket is enabled"                c_pod_socket
    check "podman-auto-update.timer is enabled"     c_pod_update
else
    pending "not run yet — podman, socket, auto-update"
fi

checks_summary
