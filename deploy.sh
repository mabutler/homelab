#!/usr/bin/env bash
# deploy.sh — put application units where Quadlet will find them.
#
#   ./deploy.sh                 every app in apps/
#   ./deploy.sh vaultwarden     just this one
#   ./deploy.sh --no-start      link and reload, but do not start anything
#   ./deploy.sh --no-publish    start apps, but do not touch tailscale serve
#   ./deploy.sh --remove NAME   unlink it (does not stop or delete anything)
#   ./deploy.sh --list          what is deployed
#
# Units are SYMLINKED from apps/<name>/ into /etc/containers/systemd/, not
# copied. `git pull` then `systemctl restart <app>` is therefore the whole
# update path, and there is never a deployed copy that has drifted from the
# repository.
#
# Deploying an app means: its state directories exist, its secrets are in place
# with the right mode, its unit is linked and started, and it is REACHABLE.
# That last one is here rather than in a manual step because `tailscale serve`
# lives in tailscaled's state and does not survive a rebuild — see
# lib/publish.sh and apps/<name>/serve.conf.
#
# Idempotent.

# shellcheck source=lib/common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/common.sh"
# shellcheck source=lib/publish.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib/publish.sh"

QUADLET_DIR=/etc/containers/systemd
SECRETS_DIR=/etc/homelab/apps
APPS_DIR="$REPO_ROOT/apps"
TMPFILES_SRC="$REPO_ROOT/system/tmpfiles"

# Quadlet reads these; anything else in an app directory is documentation.
UNIT_GLOBS=(.container .network .volume .pod .kube .build .image)

usage() {
    sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

list_apps() {
    local d
    for d in "$APPS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        basename -- "${d%/}"
    done
}

# The systemd services an app resolves to. Quadlet names a generated service
# after its file, so apps/immich/immich-database.container becomes
# immich-database.service — an app is NOT one service named after its
# directory, and Immich is four.
#
# Only .container generates a plain service worth starting and health-checking.
# .network and .volume generate oneshot units that their containers pull in.
app_services() {
    local app="$1" f
    for f in "$APPS_DIR/$app"/*.container; do
        [[ -f "$f" ]] || continue
        basename -- "$f" .container
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

    # Secrets live in the repo, gitignored, next to the unit that consumes
    # them, and are symlinked into /etc/homelab/apps/ — so every secret on this
    # host is discoverable in one directory (one thing to back up, one thing to
    # restore) while the file you actually edit sits with its app.
    #
    # A missing one stops the deploy with instructions rather than being
    # invented. Same contract as host.conf: the repository ships an example,
    # you make the real file, nothing guesses on your behalf. An auto-created
    # file full of placeholders is a file you can forget to edit.
    #
    # Permissions and the symlink ARE handled here — that is mechanical work,
    # not a decision.
    local example
    for example in "$dir"/*.env.example; do
        [[ -f "$example" ]] || continue

        local real link
        real="${example%.example}"
        link="$SECRETS_DIR/$(basename -- "$real")"

        if [[ ! -f "$real" ]]; then
            die "$app needs its environment file.

    cp $example \\
       $real
    \${EDITOR:-vim} $real

Then run this again. Permissions and the symlink into $SECRETS_DIR
are handled for you."
        fi

        run chown root:root -- "$real"
        run chmod 0600 -- "$real"

        run mkdir -p -- "$SECRETS_DIR"
        run chmod 0700 -- "$SECRETS_DIR"
        if [[ -L "$link" && "$(readlink -f -- "$link")" == "$(readlink -f -- "$real")" ]]; then
            dbg "already linked: $link"
        elif [[ -e "$link" && ! -L "$link" ]]; then
            die "$link exists and is not a symlink — move it aside; this script will not replace a real file"
        else
            log "link $link -> $real"
            run ln -sfn -- "$real" "$link"
            DEPLOY_CHANGED=1
            APP_CHANGED=1
        fi
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
        APP_CHANGED=1
    done
}

# Has the secrets file been edited since the service last started?
#
# deploy.sh links units, so a changed UNIT is visible to it — but a changed
# `.env` is not. systemd reads EnvironmentFile at start and never again, and
# nothing else notices either, so editing a secret and re-running deploy.sh
# reported "already running, unit unchanged" and left the old value live. The
# setting appears applied and is not, which for something like SIGNUPS_ALLOWED
# means believing a door is shut while it is open.
#
# Comparing mtime against the service's actual start time needs no stored state
# and cannot drift.
env_newer_than_service() {
    local app="$1" dir="$2" started f
    started="$(systemctl show -p ActiveEnterTimestamp --value "$app.service" 2>/dev/null || true)"
    [[ -n "$started" ]] || return 1
    started="$(date -d "$started" +%s 2>/dev/null || true)"
    [[ -n "$started" ]] || return 1

    for f in "$dir"/*.env; do
        [[ -f "$f" ]] || continue
        (( "$(stat -c %Y -- "$f")" > started )) && return 0
    done
    return 1
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
    local mode=deploy no_start=0 no_publish=0
    local -a want=()

    while (( $# )); do
        case "$1" in
            --remove)   mode=remove ;;
            --list)     mode=list ;;
            --no-start) no_start=1 ;;
            --no-publish) no_publish=1 ;;
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
    local -a changed_apps=()
    for app in "${want[@]}"; do
        APP_CHANGED=0
        if [[ "$mode" == remove ]]; then
            remove_app "$app"
        else
            deploy_app "$app"
            (( APP_CHANGED )) && changed_apps+=("$app")
        fi
    done

    # Quadlet turns .container files into services at daemon-reload, so nothing
    # exists to start until this runs.
    if (( DEPLOY_CHANGED )); then
        unit_reload
    else
        dbg "nothing changed"
    fi

    [[ "$mode" == deploy ]] || return 0
    if (( no_start )); then
        log "--no-start: units are linked but nothing was started"
        return 0
    fi

    # Start what is not running; restart what is running and whose unit moved.
    #
    # Boot-time startup is NOT handled here: Quadlet honours the [Install]
    # section inside the .container file, so `systemctl enable` is neither
    # needed nor meaningful for a generated unit.
    printf '\n' >&2
    local failed=0
    for app in "${want[@]}"; do
        local was_changed=0 env_changed=0 a svc
        for a in ${changed_apps[@]+"${changed_apps[@]}"}; do
            [[ "$a" == "$app" ]] && was_changed=1
        done
        env_newer_than_service "$app" "$APPS_DIR/$app" && env_changed=1

        local -a services=()
        mapfile -t services < <(app_services "$app")
        (( ${#services[@]} > 0 )) || { warn "$app has no .container units"; continue; }

        # Start every service the app resolves to. Ordering is systemd's job —
        # the units declare Requires=/After= between themselves — so asking for
        # all of them in any order is correct, and asking for one that a
        # dependency already started is a no-op.
        for svc in "${services[@]}"; do
            local is_active=0 why=''
            systemctl is-active --quiet "$svc.service" 2>/dev/null && is_active=1

            if (( was_changed )); then
                why='its unit changed'
            elif (( is_active && env_changed )); then
                why='its environment file changed since it started'
            fi

            if (( is_active )) && [[ -z "$why" ]]; then
                ok "$svc already running, nothing changed"
                continue
            fi

            if (( is_active )); then
                log "restarting $svc — $why"
                run systemctl restart "$svc.service"
            else
                log "starting $svc"
                run systemctl start "$svc.service"
            fi
        done

        [[ -n "$DRY_RUN" ]] && continue

        # Judge them all after starting them all: a database that is still
        # doing first-run initialisation would otherwise be declared broken
        # while the server waiting on it has not been asked to start yet.
        sleep 2
        for svc in "${services[@]}"; do
            if systemctl is-active --quiet "$svc.service"; then
                ok "$svc is running"
            else
                err "$svc did not start"
                systemctl status --no-pager --lines=15 "$svc.service" >&2 || true
                failed=$(( failed + 1 ))
            fi
        done
    done

    (( failed == 0 )) || die "$failed service(s) failed to start"

    # Reachability. Every app that declares a serve.conf gets its Tailscale
    # state converged to match it — after the service is confirmed up, because
    # publishing something that is not running is how you end up debugging a
    # 502 from a phone on cellular.
    #
    # This is not "set up once". It runs every deploy, so a rebuilt host walks
    # out of run.sh + deploy.sh already reachable, with no step that lives only
    # in a runbook.
    if (( no_publish )); then
        log "--no-publish: tailscale serve state left alone"
        return 0
    fi

    PUBLISH_CHANGED=0
    for app in "${want[@]}"; do
        # Publish only what is actually serving. For a multi-container app the
        # serve target belongs to one of them; if any service is down the app
        # is not ready to be reachable.
        local all_up=1 svc
        while read -r svc; do
            systemctl is-active --quiet "$svc.service" 2>/dev/null || all_up=0
        done < <(app_services "$app")
        (( all_up )) || { dbg "$app not fully up, not publishing"; continue; }
        publish_app "$app" "$APPS_DIR/$app"
    done
    (( PUBLISH_CHANGED )) || dbg "publishing already converged"
}

main "$@"
