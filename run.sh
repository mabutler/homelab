#!/usr/bin/env bash
# run.sh — run the bootstrap/ scripts, in order, on the installed system.
#
# bootstrap/ is idempotent by contract: running this twice produces no changes
# on the second pass. install/ is the destructive half and is NOT run from
# here — those scripts are invoked one at a time, from the live ISO, by hand.

source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
    cat <<'EOF'
usage: run.sh [options]

  --only NN[,NN]    run only these numbered steps (e.g. --only 40,50)
  -h, --help        this

Steps are the two-digit prefixes of the scripts in bootstrap/.
A bare `run.sh` runs all of them in order.
EOF
}

main() {
    local only=''

    while (( $# )); do
        case "$1" in
            --only)      only="${2:?--only needs a step number}"; shift ;;
            --only=*)    only="${1#*=}" ;;
            -h|--help)   usage; return 0 ;;
            *)           usage >&2; die "unknown argument: $1" ;;
        esac
        shift
    done

    local -a scripts=()
    local s
    for s in "$REPO_ROOT"/bootstrap/[0-9][0-9]-*.sh; do
        [[ -f "$s" ]] && scripts+=("$s")
    done
    (( ${#scripts[@]} > 0 )) || die "no scripts found in $REPO_ROOT/bootstrap/"

    # Fail fast on configuration before touching the machine, rather than
    # three steps in. Each script re-loads these itself (convention 4); this
    # is the early check, not the load that matters.
    require_root
    require_installed_system
    load_host_conf
    load_drives_conf

    local -a selected=()
    for s in "${scripts[@]}"; do
        local n
        n="$(step_of "$s")"
        [[ -n "$only" ]] && ! in_csv "$n" "$only" && continue
        selected+=("$s")
    done
    (( ${#selected[@]} > 0 )) || die "no bootstrap steps matched the given filters"

    # Bootstrap steps start daemons, and a daemon that needs a not-yet-loaded
    # module cannot get one after a kernel update until the machine reboots.
    # Warn rather than refuse: most steps are unaffected, and you may have a
    # good reason to press on.
    if [[ ! -d "/usr/lib/modules/$(uname -r)" ]]; then
        warn "the running kernel ($(uname -r)) no longer has its modules on disk —"
        warn "a kernel update has landed since boot. Daemons needing a new module"
        warn "will fail until you reboot."
    fi

    local failed=''
    for s in "${selected[@]}"; do
        log "── $(basename -- "$s")"
        if ! bash -- "$s"; then
            failed="$(basename -- "$s")"
            break
        fi
    done

    if [[ -n "$failed" ]]; then
        die "$failed failed — stopping here, nothing after it ran"
    fi

    ok "bootstrap complete (${#selected[@]} step(s))"
    log "next: tools/verify.sh"
}

step_of() {
    local b
    b="$(basename -- "$1")"
    printf '%s\n' "${b:0:2}"
}

# in_csv <needle> <a,b,c>
in_csv() {
    local needle="$1" list="$2" item
    local IFS=','
    for item in $list; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

main "$@"
