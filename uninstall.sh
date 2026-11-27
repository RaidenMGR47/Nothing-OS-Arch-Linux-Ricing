#!/usr/bin/env bash
# Glyph uninstaller.
#
#   ./uninstall.sh                 remove the symlinks, restore the newest ~/.dots-backup-*,
#                                  remove the SDDM theme and the ydotool udev rule
#   ./uninstall.sh --dry-run       print what would be done
#   ./uninstall.sh --no-restore    do not restore old configs (keep the backup untouched)
#   ./uninstall.sh --packages      also offer to remove the Glyph-specific AUR packages
#
# It never disables SDDM, never removes Hyprland/Quickshell/SDDM and never deletes this repo.
set -euo pipefail

DOTS=$(cd -- "$(dirname -- "$0")" && pwd)
GLYPH_STAMP=$(date +%F_%H-%M-%S)
export DOTS GLYPH_STAMP

. "$DOTS/lib/common.sh"
. "$DOTS/lib/manifest.sh"

DRY_RUN=0
YES=0
RESTORE=1
REMOVE_SDDM=1
REMOVE_PACKAGES=0
BACKUP=

usage() {
    cat <<'EOF'
Glyph uninstaller

Usage: ./uninstall.sh [options]

  --dry-run         print every change, touch nothing
  --no-restore      remove Glyph but do not restore ~/.dots-backup-*
  --keep-sddm       leave /usr/share/sddm/themes/glyph and zz-glyph.conf alone
  --packages        also remove the Glyph-specific AUR packages (asks first;
                    with --yes it removes them, including zen-browser-bin)
  -y, --yes         non-interactive; answer yes to confirmations
  -h, --help        this help

It removes only symlinks that point into this repo, restores the newest ~/.dots-backup-* (older copies
are left untouched) and the oldest system keyboard .glyph-backup-*, and deletes the SDDM theme,
zz-glyph.conf and the ydotool udev rule. SDDM itself,
Hyprland, Quickshell and the repo stay installed. Run as your user, never with sudo.
EOF
}

while [ $# -gt 0 ]; do
    case $1 in
        --dry-run) DRY_RUN=1; shift ;;
        --no-restore) RESTORE=0; shift ;;
        --keep-sddm) REMOVE_SDDM=0; shift ;;
        --packages) REMOVE_PACKAGES=1; shift ;;
        -y|--yes) YES=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done

export YES

latest_backup() {
    local b
    for b in "$HOME"/.dots-backup-*; do
        [ -d "$b" ] && printf '%s\n' "$b"
    done | sort | tail -n 1
}

remove_link() { # path
    local path=$1
    if [ ! -L "$path" ]; then
        [ -e "$path" ] && warn "not a symlink, leaving it: $path"
        return 0
    fi
    if ! is_repo_link "$path"; then
        warn "symlink points elsewhere, leaving it: $path -> $(readlink -- "$path" 2>/dev/null || true)"
        return 0
    fi
    run rm -f -- "$path"
    [ "$DRY_RUN" = 1 ] || ok "removed $path"
}

restore_backup() { # backup_dir
    local b=$1 dst rel restored=0 l
    for l in "${LINKS[@]}"; do
        read -r _ dst <<<"$l"
        rel=${dst#"$HOME"/}
        [ -e "$b/$rel" ] || [ -L "$b/$rel" ] || continue
        if [ -L "$b/$rel" ] && is_repo_link "$b/$rel"; then
            warn "backup entry points into this repo, skipping: $b/$rel"
            continue
        fi
        dst="$HOME/$rel"
        if [ -L "$dst" ]; then
            if is_repo_link "$dst"; then
                run rm -f -- "$dst"
            else
                warn "current $dst is a symlink to somewhere else; keeping both"
                continue
            fi
        elif [ -e "$dst" ]; then
            warn "current $dst exists and is not a Glyph symlink; backup kept at $b/$rel"
            continue
        fi
        run mkdir -p -- "$(dirname -- "$dst")"
        run mv -- "$b/$rel" "$dst"
        restored=$((restored + 1))
        info "$dst"
    done
    if [ "$restored" -gt 0 ] && [ "$DRY_RUN" = 0 ]; then
        ok "restored $restored path(s) from $b"
    fi
}

restore_system_backups() {
    local base latest
    for base in /etc/vconsole.conf /etc/X11/xorg.conf.d/00-keyboard.conf; do
        # The oldest copy is the pre-Glyph original; newer ones were made by later installs.
        latest=$(find "$(dirname -- "$base")" -maxdepth 1 -name "$(basename -- "$base").glyph-backup-*" -type f 2>/dev/null |
            sort | head -n 1 || true)
        if [ -z "$latest" ]; then
            info "no system backup for $base; leaving it as is"
            continue
        fi
        if [ -e "$base" ]; then
            run sudo cp -a -- "$base" "$base.glyph-uninstall-${GLYPH_STAMP}"
        fi
        run sudo cp -a -- "$latest" "$base"
        [ "$DRY_RUN" = 1 ] || ok "restored $base from $latest"
    done
}

remove_generated() {
    local state=${XDG_STATE_HOME:-$HOME/.local/state}/rice/shell
    if [ -f "$state" ] && [ "$(cat "$state")" = glyph ]; then
        run rm -f -- "$state"
        [ "$DRY_RUN" = 1 ] || ok "removed $state"
    fi
    if [ -f /etc/udev/rules.d/70-glyph-uinput.rules ] &&
        grep -q 'uinput' /etc/udev/rules.d/70-glyph-uinput.rules; then
        run sudo rm -f -- /etc/udev/rules.d/70-glyph-uinput.rules
        run sudo udevadm control --reload-rules
        [ "$DRY_RUN" = 1 ] || ok "removed the ydotool udev rule"
    fi
}

remove_sddm() {
    if [ -f /etc/sddm.conf.d/zz-glyph.conf ] &&
        grep -qsE '^[[:space:]]*Current=glyph' /etc/sddm.conf.d/zz-glyph.conf; then
        run sudo rm -f -- /etc/sddm.conf.d/zz-glyph.conf
        [ "$DRY_RUN" = 1 ] || ok "removed /etc/sddm.conf.d/zz-glyph.conf"
    fi
    if [ -d /usr/share/sddm/themes/glyph ]; then
        run sudo rm -rf /usr/share/sddm/themes/glyph
        [ "$DRY_RUN" = 1 ] || ok "removed /usr/share/sddm/themes/glyph"
    fi
}

remove_packages() {
    local p installed=()
    for p in "${PACKAGES_AUR[@]}"; do
        pkg_installed "$p" && installed+=("$p")
    done
    if [ ${#installed[@]} -eq 0 ]; then
        info "no Glyph-specific AUR packages installed"
        return 0
    fi
    info "optional AUR packages: ${installed[*]}"
    if confirm "Remove them? (zen-browser-bin is your browser)" n; then
        run sudo pacman -Rns --noconfirm "${installed[@]}"
        [ "$DRY_RUN" = 1 ] || ok "removed ${installed[*]}"
    fi
}

cleanup_dirs() {
    local d
    for d in \
        "$HOME/.config/quickshell/glyph" \
        "$HOME/.config/quickshell/rice" \
        "$HOME/.config/quickshell" \
        "$HOME/.config/demonshot" \
        "$HOME/.local/state/rice" \
        "$HOME/.local/bin"; do
        if [ -L "$d" ] || [ ! -d "$d" ]; then
            continue
        fi
        if [ "$DRY_RUN" = 1 ]; then
            info "[dry-run] would remove $d if empty"
        else
            rmdir -- "$d" 2>/dev/null || true
        fi
    done
}
preflight() {
    say "preflight"
    [ -d "$DOTS/config" ] || die "run uninstall.sh from the Glyph repo root"
    [ -f "$DOTS/lib/manifest.sh" ] || die "lib/ is missing; re-clone the repo"
    if [ "${EUID:-$(id -u)}" = 0 ]; then
        die "run as your user, not root: sudo asks when it needs to"
    fi
    case $DOTS in
        /|"$HOME") die "refusing to run from $DOTS" ;;
    esac
    info "repo: $DOTS"
    info "user: ${USER:-$(id -un)}"
}

main() {
    preflight

    local b remaining
    local -a older=()
    BACKUP=$(latest_backup || true)
    if [ -n "$BACKUP" ]; then
        info "newest backup: $BACKUP"
        for b in "$HOME"/.dots-backup-*; do
            [ -d "$b" ] || continue
            [ "$b" = "$BACKUP" ] && continue
            older+=("$(basename -- "$b")")
        done
        if [ ${#older[@]} -gt 0 ]; then
            warn "older backups are left untouched (restore by hand if needed): ${older[*]}"
        fi
    else
        warn "no ~/.dots-backup-* found; old configs cannot be restored"
    fi

    # Ask for sudo before touching anything: if authentication fails, nothing is half-removed.
    if [ "$DRY_RUN" = 0 ]; then
        sudo_start
    fi

    step "remove symlinks"
    local dst l
    for l in "${LINKS[@]}"; do
        read -r _ dst <<<"$l"
        remove_link "$HOME/$dst"
    done

    if [ "$RESTORE" = 1 ]; then
        step "restore backups"
        if [ -n "$BACKUP" ]; then
            restore_backup "$BACKUP"
        else
            warn "nothing to restore"
        fi
        restore_system_backups
    else
        info "old configs not restored (--no-restore)"
    fi

    if [ "$REMOVE_SDDM" = 1 ]; then
        step "login theme"
        remove_sddm
    fi

    step "generated files"
    remove_generated

    if [ "$REMOVE_PACKAGES" = 1 ]; then
        step "packages"
        remove_packages
    fi

    cleanup_dirs
    sudo_stop

    printf '\n'
    ok "Glyph removed"
    info "SDDM, Hyprland, Quickshell and this repo were left installed"
    if [ -n "$BACKUP" ]; then
        remaining=$(find "$BACKUP" -mindepth 1 \( -type f -o -type l \) -print -quit 2>/dev/null || true)
        [ -n "$remaining" ] && info "unrestored entries remain in $BACKUP"
    fi
    [ "$REMOVE_PACKAGES" = 1 ] || info "packages were not removed (use --packages to remove the optional AUR ones)"
}

main "$@"
