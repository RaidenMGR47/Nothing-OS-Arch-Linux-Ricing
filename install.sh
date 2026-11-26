#!/usr/bin/env bash
# Glyph installer for Arch Linux, plus a --links mode for other distros.
#
#   ./install.sh                      packages + services + symlinks + keyboard + login theme
#   ./install.sh --with telegram      same, extras picked up front (--with "" for none)
#   ./install.sh --links              symlinks + user.lua only (no packages, any distro)
#   ./install.sh --sddm               login theme only (sudo)
#   ./install.sh --check              detect keyboard/monitors and print versions, change nothing
#
# Keyboard: detects the layout from user.lua, Hyprland, localectl, vconsole.conf,
# 00-keyboard.conf, setxkbmap, /etc/default/keyboard or the locale; writes it to hypr/user.lua
# and (unless --no-system-keyboard) keeps the console and X11 in sync. Override with
# --keyboard latam[,us].
#
# Monitors: reports every connected DRM output. A connected output without modes means EDID/DDC
# failed; force it with --monitor DVI-I-1:1366x768@60.
set -euo pipefail

DOTS=$(cd -- "$(dirname -- "$0")" && pwd)
GLYPH_STAMP=$(date +%F_%H-%M-%S)
BACKUP="$HOME/.dots-backup-$GLYPH_STAMP"
export DOTS GLYPH_STAMP BACKUP

. "$DOTS/lib/common.sh"
. "$DOTS/lib/manifest.sh"
. "$DOTS/lib/keyboard.sh"
. "$DOTS/lib/monitor.sh"

MODE=full
WITH=
WITH_SET=0
KEYBOARD=auto
KB_OPTIONS_FORCE=
KB_OPTIONS_SET=0
NO_SYSTEM_KEYBOARD=0
KEEP_DM=0
NO_AUR=0
YES=0
CHECK_ONLY=0
declare -a EXT=()

usage() {
    cat <<'EOF'
Glyph installer

Usage: ./install.sh [options]

  --with LIST            extras: telegram, spotify, clash (comma or space separated;
                         "" or --with with no value for none)
  --links                symlinks + user.lua only, no packages/services (any distro)
  --sddm                 copy the SDDM theme and set it, nothing else
  --keyboard LAYOUT      force the XKB layout(s), e.g. latam, "latam,us"; default: auto
  --kb-options OPTIONS   force XKB options, e.g. grp:alt_shift_toggle
  --no-system-keyboard   leave /etc/vconsole.conf and 00-keyboard.conf alone
  --monitor SPEC         add a monitor rule: OUTPUT:MODE[:POSITION[:SCALE]]
                         e.g. --monitor DVI-I-1:1366x768@60
                         can be repeated
  --keep-dm              do not enable/disable display managers
  --no-aur               skip yay and the AUR packages
  --check                detect keyboard/monitors and print versions, change nothing
  -y, --yes              non-interactive; no extras unless --with, yes to prompts
  -h, --help             this help

Without --with the installer asks which extras to add (not with --yes). Old configs go to
~/.dots-backup-<date>/. Run as your user, never with sudo.
EOF
}

while [ $# -gt 0 ]; do
    case $1 in
        --with)
            WITH_SET=1
            if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then
                WITH=$2
                shift 2
            else
                WITH=
                shift
            fi
            ;;
        --with=*) WITH=${1#*=}; WITH_SET=1; shift ;;
        --links) MODE=links; shift ;;
        --sddm) MODE=sddm; shift ;;
        --keyboard)
            [ $# -ge 2 ] || die "--keyboard needs a value (e.g. latam)"
            KEYBOARD=$2
            shift 2
            ;;
        --keyboard=*) KEYBOARD=${1#*=}; shift ;;
        --kb-options)
            [ $# -ge 2 ] || die "--kb-options needs a value"
            KB_OPTIONS_FORCE=$2
            KB_OPTIONS_SET=1
            shift 2
            ;;
        --kb-options=*) KB_OPTIONS_FORCE=${1#*=}; KB_OPTIONS_SET=1; shift ;;
        --no-system-keyboard) NO_SYSTEM_KEYBOARD=1; shift ;;
        --monitor)
            [ $# -ge 2 ] || die "--monitor needs OUTPUT:MODE (e.g. DVI-I-1:1366x768@60)"
            mon_add_rule "$2"
            shift 2
            ;;
        --monitor=*) mon_add_rule "${1#*=}"; shift ;;
        --keep-dm) KEEP_DM=1; shift ;;
        --no-aur) NO_AUR=1; shift ;;
        --check) CHECK_ONLY=1; MODE=check; shift ;;
        -y|--yes) YES=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done

# --yes is non-interactive: do not ask for extras unless --with was given.
if [ "$YES" = 1 ] && [ "$WITH_SET" = 0 ]; then
    WITH_SET=1
    WITH=
fi

# confirm() in lib/common.sh reads YES from the environment of the sourced functions.
export YES

preflight() {
    say "preflight"
    [ -d "$DOTS/config" ] || die "run install.sh from the Glyph repo root"
    [ -f "$DOTS/lib/manifest.sh" ] || die "lib/ is missing; re-clone the repo"
    if [ "${EUID:-$(id -u)}" = 0 ] && [ "$CHECK_ONLY" != 1 ]; then
        die "run as your user, not root: sudo asks when it needs to"
    fi
    case $DOTS in
        /|"$HOME") die "refusing to run from $DOTS" ;;
    esac
    info "repo: $DOTS"
    info "user: ${USER:-$(id -un)} (uid ${EUID:-$(id -u)})"

    if [ "$MODE" = links ] || [ "$MODE" = sddm ] || [ "$MODE" = check ]; then
        return 0
    fi
    if ! have pacman; then
        die "packages install on Arch only; on another distro run: $0 --links"
    fi
    if [ ! -f /etc/arch-release ]; then
        warn "no /etc/arch-release, but pacman exists; continuing"
    fi
    if [ ! -d /run/systemd/system ]; then
        warn "systemd is not PID 1; services will be skipped"
    fi
    have sudo || die "sudo is required"
}

preflight_files() {
    local src dst l
    for l in "${LINKS[@]}"; do
        read -r src dst <<<"$l"
        [ -e "$DOTS/$src" ] || warn "missing in repo: $src"
    done
    [ -f "$DOTS/config/hypr/user.lua.example" ] || warn "missing: config/hypr/user.lua.example"
}

extras() {
    local w
    EXT=()
    if [ "$WITH_SET" = 0 ]; then
        if [ ! -t 0 ]; then
            WITH=
        else
            say "extras"
            info "space-separated, Enter for none"
            for w in "${!EXTRA[@]}"; do
                printf '  %-9s %s\n' "$w" "${EXTRA[$w]}"
            done
            printf '  > '
            read -r WITH || true
        fi
    fi
    for w in ${WITH//,/ }; do
        [ -n "${EXTRA[$w]-}" ] || die "no such extra: $w (available: ${!EXTRA[*]})"
        # shellcheck disable=SC2206
        EXT+=(${EXTRA[$w]})
    done
    if [ ${#EXT[@]} -gt 0 ]; then
        info "extras: ${EXT[*]}"
    fi
}

aur_install() { # helper pkg... — interactive unless --yes, so PKGBUILDs can be reviewed
    local helper=$1
    shift
    if [ "$YES" = 1 ]; then
        "$helper" -S --needed --noconfirm "$@"
    else
        "$helper" -S --needed "$@"
    fi
}

packages() {
    say "pacman"
    local pa p helper tmp
    local -a avail=() missing=() makepkg_args=() pac_args=()

    if [ "$YES" = 1 ]; then
        pac_args=(--noconfirm)
    fi

    # PulseAudio conflicts with pipewire-pulse. With --noconfirm pacman answers "no" to
    # "Remove pulseaudio? [y/N]" and aborts the transaction, so remove it beforehand in --yes mode.
    pa=$(pacman -Qq pulseaudio-{bluetooth,jack,lirc,rtp,zeroconf,equalizer,equalizer-ladspa} 2>/dev/null || true)
    if pacman -Q pulseaudio >/dev/null 2>&1; then
        if [ "$YES" = 1 ]; then
            pa="${pa:+$pa }pulseaudio"
        else
            warn "pacman will ask to replace pulseaudio with pipewire-pulse: answer yes"
        fi
    fi
    if [ -n "$pa" ]; then
        warn "removing PulseAudio packages that conflict with PipeWire: $pa"
        # shellcheck disable=SC2086
        if ! sudo pacman -R --noconfirm $pa; then
            if [ "$YES" = 1 ] && pacman -Q pulseaudio >/dev/null 2>&1; then
                warn "plain removal failed; forcing removal of the conflicting PulseAudio packages"
                # shellcheck disable=SC2086
                sudo pacman -Rdd --noconfirm $pa || die "cannot remove PulseAudio; install pipewire-pulse manually"
            else
                warn "could not remove: $pa"
            fi
        fi
    fi

    # Upgrade the database first: with stale mirrors a package added upstream would be reported
    # as unknown and make the whole transaction abort. Then install everything that exists, so a
    # renamed optional package cannot take the session down.
    if ! sudo pacman -Syu "${pac_args[@]}"; then
        die "pacman -Syu failed. If it is a keyring error: sudo pacman -Sy archlinux-keyring && sudo pacman -Su"
    fi
    for p in "${PACMAN[@]}"; do
        if pacman -Si "$p" >/dev/null 2>&1 || pacman -Sgq "$p" >/dev/null 2>&1; then
            avail+=("$p")
        else
            missing+=("$p")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        warn "not in the configured repos, skipping: ${missing[*]}"
    fi
    [ ${#avail[@]} -gt 0 ] || die "none of the packages are available; check your mirrors"
    if ! sudo pacman -S --needed "${pac_args[@]}" "${avail[@]}"; then
        die "pacman failed. If it is a keyring error: sudo pacman -Sy archlinux-keyring && sudo pacman -Su"
    fi

    if [ "$NO_AUR" = 1 ]; then
        info "AUR: skipped (--no-aur)"
        return 0
    fi

    helper=$(aur_helper || true)
    if [ -z "$helper" ]; then
        say "yay"
        have git || die "git is required to build yay-bin"
        tmp=$(mktemp -d)
        if ! git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"; then
            rm -rf -- "$tmp"
            die "cannot clone yay-bin (network or AUR down?)"
        fi
        if [ "$YES" = 1 ]; then
            makepkg_args=(--noconfirm)
        fi
        if ! ( cd "$tmp/yay-bin" && makepkg -si "${makepkg_args[@]}" ); then
            rm -rf -- "$tmp"
            die "yay-bin failed to build"
        fi
        rm -rf -- "$tmp"
        helper=$(aur_helper || true)
        [ -n "$helper" ] || die "yay installed but not in PATH"
    fi

    say "AUR"
    if ! aur_install "$helper" "${AUR[@]}"; then
        warn "AUR: some packages failed; the rice still works without the optional ones"
    fi
    if [ ${#EXT[@]} -gt 0 ]; then
        if ! aur_install "$helper" "${EXT[@]}"; then
            warn "extras: some packages failed"
        fi
        if printf '%s\n' "${EXT[@]}" | grep -qx 'spicetify-cli'; then
            say "spicetify"
            info "launch Spotify, log in, then run:"
            dim "spicetify config custom_apps marketplace && spicetify backup apply"
        fi
    fi
}

services() {
    say "services"
    if [ ! -d /run/systemd/system ]; then
        warn "systemd is not running; skipping services"
        return 0
    fi
    local unit user_name=${USER:-$(id -un)}
    for unit in NetworkManager.service bluetooth.service power-profiles-daemon.service; do
        if sudo systemctl enable "$unit" 2>/dev/null; then
            ok "$unit"
        else
            warn "could not enable $unit"
        fi
    done
    for unit in pipewire-pulse.socket wireplumber.service ydotool.service; do
        if systemctl --user enable "$unit" 2>/dev/null; then
            ok "user: $unit"
        else
            warn "could not enable user unit $unit (start a graphical session and rerun?)"
        fi
    done
    sudo usermod -aG video "$user_name" || warn "could not add $user_name to the video group"
    # ydotool writes to /dev/uinput: grant access to the user at the seat (uaccess, like steam-devices).
    # Do not use the input group: it can read /dev/input/event* and would expose every keystroke,
    # passwords included. The rule applies after a reboot.
    printf '%s\n' 'KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"' |
        sudo tee /etc/udev/rules.d/70-glyph-uinput.rules >/dev/null
    sudo udevadm control --reload-rules 2>/dev/null || true
    sudo udevadm trigger --subsystem-match=misc 2>/dev/null || true
    xdg-user-dirs-update 2>/dev/null || true
}

links() {
    step "symlinks"
    info "old files -> $BACKUP"
    local src dst target l
    for l in "${LINKS[@]}"; do
        read -r src dst <<<"$l"
        src="$DOTS/$src"
        dst="$HOME/$dst"
        if [ ! -e "$src" ]; then
            warn "missing: $src"
            continue
        fi
        target=$(readlink -- "$dst" 2>/dev/null || true)
        [ "$target" = "$src" ] && continue
        if [ -L "$dst" ] && is_repo_link "$dst"; then
            # A previous install's own symlink: drop it, never back it up, or uninstall would
            # restore a link pointing into this repo after it is deleted.
            rm -f -- "$dst"
        elif [ -e "$dst" ] || [ -L "$dst" ]; then
            mkdir -p -- "$BACKUP/$(dirname -- "${dst#"$HOME"/}")"
            mv -- "$dst" "$BACKUP/${dst#"$HOME"/}"
        fi
        mkdir -p -- "$(dirname -- "$dst")"
        ln -s -- "$src" "$dst"
        info "$dst"
    done
    mkdir -p -- "$HOME/.config/demonshot" "${XDG_STATE_HOME:-$HOME/.local/state}/rice"
    printf 'glyph\n' >"${XDG_STATE_HOME:-$HOME/.local/state}/rice/shell"
    mkdir -p -- "$HOME/Pictures/Wallpapers" "$HOME/Pictures/Gifs"
    chmod +x -- "$DOTS/install.sh" "$DOTS/uninstall.sh" "$DOTS/config/quickshell/rice/rice" \
        "$DOTS/config/quickshell/glyph/ear" "$DOTS/config/quickshell/glyph/term/cava/dots" 2>/dev/null || true
    if have fc-cache; then
        fc-cache -f >/dev/null 2>&1 || true
    fi
    if have gsettings; then
        # Dark mode for Zen, Electron and libadwaita (through the portal), and the dark gtk3 base
        # under our gtk.css.
        gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
        gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark 2>/dev/null || true
    fi
    ok "configs linked"
}

greeter() {
    step "SDDM theme"
    if [ ! -d /usr/share/sddm/themes ]; then
        warn "SDDM is not installed; skipping the login theme"
        return 0
    fi
    [ -d "$DOTS/config/sddm/glyph" ] || die "config/sddm/glyph is missing"
    [ -d "$DOTS/config/fonts" ] || die "config/fonts is missing"

    # A copy, not a symlink: the sddm user cannot read a private $HOME.
    sudo rm -rf /usr/share/sddm/themes/glyph
    # No -L: root must not follow links out of the theme (a link to /etc/shadow would become a
    # world-readable copy after chmod). The theme's only own link, fonts -> config/fonts, is
    # replaced by the fonts themselves.
    sudo cp -rT "$DOTS/config/sddm/glyph" /usr/share/sddm/themes/glyph
    sudo rm -f /usr/share/sddm/themes/glyph/fonts
    sudo cp -rT "$DOTS/config/fonts" /usr/share/sddm/themes/glyph/fonts
    sudo chmod -R a+rX /usr/share/sddm/themes/glyph

    # InputMethod empty: sddm defaults to qtvirtualkeyboard, which covers the whole screen with
    # this theme.
    sudo mkdir -p /etc/sddm.conf.d
    if [ -f /etc/sddm.conf.d/zz-glyph.conf ] && ! grep -qsE '^[[:space:]]*Current=glyph' /etc/sddm.conf.d/zz-glyph.conf; then
        backup_file /etc/sddm.conf.d/zz-glyph.conf 1
    fi
    # zz-: conf.d is read in alphabetical order and the last file wins, so ours goes on top of
    # other themes' files.
    printf '[Theme]\nCurrent=glyph\n\n[General]\nInputMethod=\n' |
        sudo tee /etc/sddm.conf.d/zz-glyph.conf >/dev/null
    ok "theme: /usr/share/sddm/themes/glyph"
    if grep -qsE '^[[:space:]]*Current=' /etc/sddm.conf && ! grep -qsE '^[[:space:]]*Current=glyph[[:space:]]*$' /etc/sddm.conf; then
        warn "/etc/sddm.conf sets Current= and wins over /etc/sddm.conf.d: set Current=glyph there"
    fi
}

display_manager() {
    say "login manager"
    if [ "$KEEP_DM" = 1 ]; then
        info "left untouched (--keep-dm)"
        return 0
    fi
    if [ ! -d /run/systemd/system ]; then
        warn "systemd is not running; not touching display-manager"
        return 0
    fi
    if ! pkg_installed sddm 2>/dev/null && ! have sddm; then
        warn "sddm is not installed; cannot enable it"
        return 0
    fi
    local enabled dm def
    enabled=$(systemctl list-unit-files --type=service --state=enabled --no-legend 2>/dev/null |
        awk '{print $1}' |
        grep -E '^(gdm|lightdm|sddm|plasmalogin|ly|greetd|lxdm|slim|xdm)\.service$' || true)
    if [ -n "$enabled" ]; then
        info "enabled display manager(s):"
        printf '%s\n' "$enabled" | sed 's/^/    /'
        if [ "$enabled" != "sddm.service" ]; then
            if confirm "Disable them and enable SDDM for the Glyph login theme?" y; then
                for dm in $enabled; do
                    [ "$dm" = "sddm.service" ] && continue
                    sudo systemctl disable "$dm" || warn "could not disable $dm"
                done
            else
                warn "keeping the current display manager; the Glyph theme is installed but may not be used"
                return 0
            fi
        fi
    fi
    if sudo systemctl enable sddm.service; then
        ok "sddm.service enabled"
    else
        warn "could not enable sddm.service"
    fi
    def=$(systemctl get-default 2>/dev/null || true)
    if [ -n "$def" ] && [ "$def" != "graphical.target" ]; then
        if confirm "Set graphical.target as the default boot target?" y; then
            sudo systemctl set-default graphical.target || warn "could not set graphical.target"
        fi
    fi
}

check_one() {
    local pkg=$1 need=$2 label=$3 ver
    if ! pkg_installed "$pkg"; then
        warn "$label is not installed"
        return 0
    fi
    ver=$(pkg_version "$pkg")
    if version_ge "$ver" "$need"; then
        ok "$label $ver"
    else
        warn "$label $ver is older than $need; run sudo pacman -Syu"
    fi
}

check_versions() {
    say "versions"
    if ! have pacman; then
        info "not Arch; skipping package version checks"
        return 0
    fi
    check_one hyprland 0.56.0 "Hyprland"
    check_one quickshell 0.3.1 "Quickshell"
    check_one sddm 0.21.0 "SDDM"
}

summary() {
    printf '\n'
    ok "done"
    info "keyboard: $KB_LAYOUT ($KB_SOURCE)"
    if [ ${#MON_OUTPUTS[@]} -gt 0 ]; then
        info "monitors: ${MON_OUTPUTS[*]}"
    fi
    if [ -d "$BACKUP" ]; then
        info "old configs: $BACKUP"
    fi
    info "reboot and pick Hyprland in SDDM"
    mon_suggest
    if [ "$MODE" = links ]; then
        info "system keyboard untouched in --links mode; run ./install.sh for console/X11"
    fi
}

main() {
    preflight
    preflight_files

    kb_detect "$KEYBOARD" "$KB_OPTIONS_FORCE" "$KB_OPTIONS_SET"
    mon_detect
    mon_validate_rules
    kb_report
    mon_report

    if [ "$CHECK_ONLY" = 1 ]; then
        check_versions
        mon_suggest
        printf '\n'
        ok "check only: nothing was changed"
        return 0
    fi

    if [ "$MODE" = sddm ]; then
        sudo_start
        greeter
        sudo_stop
        return 0
    fi

    kb_confirm
    mon_prompt
    mon_validate_rules

    if [ "$MODE" = links ]; then
        links
        kb_apply_user_lua "$DOTS/config/hypr/user.lua"
        mon_apply_user_lua "$DOTS/config/hypr/user.lua"
        summary
        return 0
    fi

    extras
    sudo_start
    packages
    services
    links
    kb_apply_user_lua "$DOTS/config/hypr/user.lua"
    kb_apply_system "$NO_SYSTEM_KEYBOARD"
    mon_apply_user_lua "$DOTS/config/hypr/user.lua"
    greeter
    display_manager
    check_versions
    sudo_stop
    summary
}

main "$@"
