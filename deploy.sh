#!/usr/bin/env bash
# deploy.sh — put application units where Quadlet will find them.
#
#   ./deploy.sh                 every app in apps/
#   ./deploy.sh vaultwarden     just this one
#   ./deploy.sh --remove NAME   unlink it (does not stop or delete anything)
#   ./deploy.sh --list          what is deployed
#
# Units are SYMLINKED from apps/<name>/ into /etc/containers/systemd/, not
# copied. `git pull` then `systemctl restart <app>` is therefore the whole
# update path, and there is never a deployed copy that has drifted from the
# repository.
#
# Idempotent.

# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"

QUADLET_DIR=/etc/containers/systemd
SECRETS_DIR=/etc/homelab/apps
APPS_DIR="$REPO_ROOT/apps"
TMPFILES_SRC="$REPO_ROOT/system/tmpfiles"

# Quadlet reads these; anything else in an app directory is documentation.
UNIT_GLOBS=(.container .network .volume .pod .kube .build .image)

usage() {
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

list_apps() {
    local d
    for d in "$APPS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        basename -- "${d%/}"
    done
}

# Every unit file an app directory contributes.
app_units() {
    local app="$1" f ext
    for ext in "${UNIT_GLOBS[@]}"; do
        for f in "$APPS_DIR/$app"/*"$ext"; do
            [[ -f "$f" ]] && printf '%s\n' "$f"
        done
    done
}

deploy_app() {
    local app="$1"
    local dir="$APPS_DIR/$app"
    [[ -d "$dir" ]] || die "no such app: $app (looked in $dir)"

    local -a units=()
    mapfile -t units < <(app_units "$app")
    (( ${#units[@]} > 0 )) || die "$app has no Quadlet unit files"

    # An app that ships a .env.example needs a real one before it can start.
    # Catching that here beats a container that starts, finds an empty
    # DOMAIN, and half-works in a way that is painful to unpick later.
    local example
    for example in "$dir"/*.env.example; do
        [[ -f "$example" ]] || continue
        local env_path perms
        env_path="$SECRETS_DIR/$(basename -- "${example%.example}")"
        if [[ ! -f "$env_path" ]]; then
            die "$app needs $env_path
Copy $example there, fill it in, and chmod 0600."
        fi
        perms="$(stat -c '%a %U' -- "$env_path")"
        [[ "$perms" == "600 root" ]] \
            || die "$env_path is $perms — must be 600 root. It holds credentials."
    done

    local f target
    for f in "${units[@]}"; do
        target="$QUADLET_DIR/$(basename -- "$f")"
        if [[ -L "$target" && "$(readlink -f -- "$target")" == "$(readlink -f -- "$f")" ]]; then
            dbg "already linked: $(basename -- "$f")"
            continue
        fi
        if [[ -e "$target" && ! -L "$target" ]]; then
            die "$target exists and is not a symlink — refusing to replace a file this script did not create"
        fi
        log "link $(basename -- "$f")"
        run ln -sfn -- "$f" "$target"
        DEPLOY_CHANGED=1
    done
}

remove_app() {
    local app="$1" f target
    while read -r f; do
        target="$QUADLET_DIR/$(basename -- "$f")"
        [[ -L "$target" ]] || continue
        log "unlink $(basename -- "$f")"
        run rm -f -- "$target"
        DEPLOY_CHANGED=1
    done < <(app_units "$app")
    warn "units unlinked. Running containers are untouched:  systemctl stop $app"
}

main() {
    local mode=deploy
    local -a want=()

    while (( $# )); do
        case "$1" in
            --remove) mode=remove ;;
            --list)   mode=list ;;
            -h|--help) usage; return 0 ;;
            -v|--verbose) VERBOSE=1 ;;
            -*) usage >&2; die "unknown argument: $1" ;;
            *)  want+=("$1") ;;
        esac
        shift
    done

    if [[ "$mode" == list ]]; then
        local l
        for l in "$QUADLET_DIR"/*; do
            [[ -e "$l" ]] || continue
            printf '%-32s -> %s\n' "$(basename -- "$l")" "$(readlink -f -- "$l")"
        done
        return 0
    fi

    require_root
    require_installed_system
    load_host_conf

    [[ -d "$QUADLET_DIR" ]] || die "$QUADLET_DIR does not exist — run bootstrap/70-podman.sh first"

    (( ${#want[@]} > 0 )) || mapfile -t want < <(list_apps)
    (( ${#want[@]} > 0 )) || die "no apps in $APPS_DIR"

    DEPLOY_CHANGED=0

    # State directories first: a Quadlet unit that starts before its volume path
    # exists gets a root-owned directory created by podman instead, with
    # whatever permissions podman felt like.
    #
    # install_file is not usable here — it resolves against files/, and these
    # live in system/tmpfiles/ because they are not host configuration in the
    # same sense; they describe directories the apps need.
    if [[ -d "$TMPFILES_SRC" ]]; then
        local t dst tmpfiles_changed=0
        for t in "$TMPFILES_SRC"/*.conf; do
            [[ -f "$t" ]] || continue
            dst="/etc/tmpfiles.d/$(basename -- "$t")"
            if [[ -f "$dst" ]] && cmp -s -- "$t" "$dst"; then
                dbg "unchanged: $dst"
                continue
            fi
            log "install $dst"
            run install -Dm644 -- "$t" "$dst"
            tmpfiles_changed=1
        done
        if (( tmpfiles_changed )); then
            run systemd-tmpfiles --create
        fi
    fi

    local app
    for app in "${want[@]}"; do
        if [[ "$mode" == remove ]]; then
            remove_app "$app"
        else
            deploy_app "$app"
        fi
    done

    if (( DEPLOY_CHANGED )); then
        unit_reload
    else
        dbg "nothing changed"
    fi

    if [[ "$mode" == deploy && -z "$DRY_RUN" ]]; then
        printf '\n' >&2
        for app in "${want[@]}"; do
            if systemctl is-active --quiet "$app.service" 2>/dev/null; then
                ok "$app is running"
            else
                log "$app is deployed but not started:  sudo systemctl start $app"
            fi
        done
    fi
}

main "$@"
