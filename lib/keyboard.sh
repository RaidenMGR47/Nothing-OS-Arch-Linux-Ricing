#!/usr/bin/env bash
# Glyph: keyboard detection and configuration.
#
# Hyprland does not read /etc/vconsole.conf or /etc/X11/xorg.conf.d/00-keyboard.conf. Its layout
# lives in hypr/hyprland/input.lua (upstream: "us,ru") and can be overridden from hypr/user.lua,
# which is loaded last. This module finds the keyboard the machine already uses, writes the
# override into user.lua and (unless --no-system-keyboard) keeps the console and X11 in sync so
# SDDM/LightDM and the TTYs match.
#
# Detection order, first hit wins:
#   1. --keyboard
#   2. an existing managed block (or any kb_layout) in hypr/user.lua
#   3. a live Hyprland session (hyprctl devices), ignoring the upstream "us,ru"
#   4. XKB_DEFAULT_LAYOUT
#   5. localectl X11 Layout (a bare "us" without 00-keyboard.conf is treated as a weak default)
#   6. /etc/X11/xorg.conf.d/00-keyboard.conf
#   7. /etc/vconsole.conf KEYMAP (la-latin1 -> latam)
#   8. setxkbmap -query (X11/XWayland)
#   9. /etc/default/keyboard (Debian and friends)
#  10. the locale (es_MX -> latam, es_ES -> es, pt_BR -> br, en_GB -> gb, ...)
#  11. us, with a warning

KB_LAYOUT=
KB_OPTIONS=
KB_SOURCE=
KB_VCONSOLE=

kb_normalize() { # XKB or vconsole name -> XKB layout
    local l
    l=$(trim "${1-}")
    l=${l//[[:space:]]/}
    l=${l,,}
    case $l in
        ""|n/a|none|auto) return 1 ;;
        la-latin1|la_latin1) l="latam" ;;
        es-latin1|es_latin1) l="es" ;;
        us-intl|us_intl|us-acentos|us_acentos)
            warn "$l is a variant of us; this installer sets the base 'us' layout"
            l="us"
            ;;
        uk) l="gb" ;;
        br-abnt2|br_abnt2) l="br" ;;
        pt-latin1|pt_latin1|pt-latin9|pt_latin9) l="pt" ;;
        cz-lat2|cz_lat2|cz-lat2-us|cz_lat2_us) l="cz" ;;
        dk-latin1|dk_latin1) l="dk" ;;
        fi-latin1|fi_latin1) l="fi" ;;
        fr-latin1|fr_latin1|fr-latin9|fr_latin9|fr-pc|fr_pc) l="fr" ;;
        de-latin1|de_latin1|de-latin1-nodeadkeys|de_latin1_nodeadkeys|de-nodeadkeys) l="de" ;;
        it2|it-2|it2-nodeadkeys) l="it" ;;
        ru4|ru-win) l="ru" ;;
        se-latin1|se_latin1) l="se" ;;
        no-latin1|no_latin1|nb|nn) l="no" ;;
        trq|tr-f|tr_f) l="tr" ;;
        ua-utf|ua_utf) l="ua" ;;
        jp106|jp) l="jp" ;;
        kr106|kr) l="kr" ;;
        latam) l="latam" ;;
    esac
    printf '%s' "$l"
}

kb_sanitize_list() { # "latam, us" -> "latam,us"; returns 1 if nothing usable
    local raw=${1-} part cleaned
    local -a parts=() out=()
    IFS=',' read -r -a parts <<<"$raw"
    for part in "${parts[@]}"; do
        part=$(trim "$part")
        [ -n "$part" ] || continue
        case $part in
            *\(*\))
                warn "keyboard variant '$part' is not handled; using its base layout"
                part=${part%%(*}
                ;;
        esac
        cleaned=$(kb_normalize "$part") || continue
        out+=("$cleaned")
    done
    [ ${#out[@]} -gt 0 ] || return 1
    local IFS=','
    printf '%s' "${out[*]}"
}

kb_default_options() { # layout
    case ${1-} in
        *,*) printf 'grp:alt_shift_toggle' ;;
        *) printf '' ;;
    esac
}

kb_vconsole_for() { # XKB layout -> vconsole keymap
    case ${1-} in
        latam) printf 'la-latin1' ;;
        us) printf 'us' ;;
        es) printf 'es' ;;
        br) printf 'br-abnt2' ;;
        pt) printf 'pt-latin1' ;;
        gb) printf 'uk' ;;
        fr) printf 'fr' ;;
        de) printf 'de' ;;
        it) printf 'it' ;;
        ru) printf 'ru' ;;
        cz) printf 'cz-lat2' ;;
        pl) printf 'pl' ;;
        tr) printf 'tr' ;;
        nl) printf 'nl' ;;
        se) printf 'se' ;;
        no) printf 'no' ;;
        dk) printf 'dk' ;;
        fi) printf 'fi' ;;
        hu) printf 'hu' ;;
        ro) printf 'ro' ;;
        gr) printf 'gr' ;;
        ua) printf 'ua' ;;
        jp) printf 'jp106' ;;
        kr) printf 'kr' ;;
        cn|tw) printf 'us' ;;
        *) printf '%s' "${1-}" ;;
    esac
}

kb_locale_name() {
    local loc=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
    loc=${loc%%.*}
    loc=${loc%%@*}
    printf '%s' "$loc"
}

kb_from_locale() {
    local loc
    loc=$(kb_locale_name)
    case $loc in
        es|es_ES) printf 'es' ;;
        es_*) printf 'latam' ;;
        pt_BR) printf 'br' ;;
        pt_*|pt) printf 'pt' ;;
        en_GB) printf 'gb' ;;
        en_*|C|POSIX|"") printf 'us' ;;
        de_*|de) printf 'de' ;;
        fr_*|fr) printf 'fr' ;;
        it_*|it) printf 'it' ;;
        ru_*|ru) printf 'ru' ;;
        pl_*|pl) printf 'pl' ;;
        tr_*|tr) printf 'tr' ;;
        nl_*|nl) printf 'nl' ;;
        sv_*|sv) printf 'se' ;;
        nb_*|nn_*|no_*|no) printf 'no' ;;
        da_*|da) printf 'dk' ;;
        fi_*|fi) printf 'fi' ;;
        cs_*|cs) printf 'cz' ;;
        hu_*|hu) printf 'hu' ;;
        ro_*|ro) printf 'ro' ;;
        el_*|el) printf 'gr' ;;
        uk_*|uk) printf 'ua' ;;
        ja_*|ja) printf 'jp' ;;
        ko_*|ko) printf 'kr' ;;
        zh_CN*|zh_SG*) printf 'cn' ;;
        zh_TW*|zh_HK*) printf 'tw' ;;
        *) printf 'us' ;;
    esac
}

kb_lua_value() { # file key -> value (may be empty); 0 if the key exists
    local file=$1 key=$2 scope has_block=0 line
    [ -f "$file" ] || return 1
    if grep -qxF -- '-- >>> glyph:keyboard' "$file"; then
        has_block=1
        scope=$(awk '/^-- >>> glyph:keyboard/{f=1;next} /^-- <<< glyph:keyboard/{f=0} f' "$file")
    else
        scope=$(cat "$file")
    fi
    if [ "$has_block" = 1 ] && [ -z "$scope" ]; then
        return 1
    fi
    line=$(printf '%s\n' "$scope" | grep -E "(^|[^[:alnum:]_])${key}[[:space:]]*=" | tail -n 1) || return 1
    if printf '%s\n' "$line" | grep -qE "${key}[[:space:]]*=[[:space:]]*\""; then
        printf '%s\n' "$line" | sed -nE "s/.*${key}[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p"
    elif printf '%s\n' "$line" | grep -qE "${key}[[:space:]]*=[[:space:]]*'"; then
        printf '%s\n' "$line" | sed -nE "s/.*${key}[[:space:]]*=[[:space:]]*'([^']*)'.*/\1/p"
    else
        return 1
    fi
}

kb_localectl_field() { # "X11 Layout", "X11 Options", "VC Keymap"
    local field=$1 out
    have localectl || return 1
    out=$(LC_ALL=C localectl status 2>/dev/null) || return 1
    printf '%s\n' "$out" | sed -nE "s/^[[:space:]]*${field}:[[:space:]]*(.*)$/\1/p" | head -n 1
}

kb_from_hyprctl() {
    have hyprctl || return 1
    have jq || return 1
    hyprctl devices -j 2>/dev/null |
        jq -r '[.keyboards[]? | select(.layout != null and .layout != "")][0].layout // empty' 2>/dev/null
}

kb_x11_conf_layout() {
    local f=/etc/X11/xorg.conf.d/00-keyboard.conf
    [ -f "$f" ] || return 1
    sed -nE 's/.*Option[[:space:]]+"XkbLayout"[[:space:]]+"([^"]*)".*/\1/p' "$f" | tail -n 1
}

kb_x11_conf_options() {
    local f=/etc/X11/xorg.conf.d/00-keyboard.conf
    [ -f "$f" ] || return 1
    sed -nE 's/.*Option[[:space:]]+"XkbOptions"[[:space:]]+"([^"]*)".*/\1/p' "$f" | tail -n 1
}

kb_vconsole_keymap() {
    local f=/etc/vconsole.conf
    [ -f "$f" ] || return 1
    sed -nE 's/^[[:space:]]*KEYMAP[[:space:]]*=[[:space:]]*"?([^"[:space:]]+)"?.*/\1/p' "$f" | tail -n 1
}

kb_from_setxkbmap() {
    have setxkbmap || return 1
    LC_ALL=C setxkbmap -query 2>/dev/null |
        sed -nE 's/^layout:[[:space:]]*(.*)$/\1/p' | head -n 1
}

kb_from_default_keyboard() {
    local f=/etc/default/keyboard
    [ -f "$f" ] || return 1
    sed -nE 's/^[[:space:]]*XKBLAYOUT[[:space:]]*=[[:space:]]*"?([^"]*)"?.*/\1/p' "$f" | tail -n 1
}

kb_set() { # layout options source vconsole(optional)
    KB_LAYOUT=$1
    KB_OPTIONS=$2
    KB_SOURCE=$3
    if [ -n "${4-}" ]; then
        KB_VCONSOLE=$4
    else
        KB_VCONSOLE=$(kb_vconsole_for "${KB_LAYOUT%%,*}")
    fi
}

kb_detect() { # forced_layout [forced_options] [options_set:0|1]
    local forced_layout=${1:-auto} forced_options=${2-} options_set=${3:-0}
    local candidate opts loc cleaned lua=$DOTS/config/hypr/user.lua
    local weak='' weak_src='' weak_vconsole=''

    KB_LAYOUT='' KB_OPTIONS='' KB_SOURCE='' KB_VCONSOLE=''

    if [ -n "$forced_layout" ] && [ "$forced_layout" != auto ]; then
        KB_LAYOUT=$(kb_sanitize_list "$forced_layout") || die "invalid --keyboard value: $forced_layout"
        if [ "$options_set" = 1 ]; then
            KB_OPTIONS=$forced_options
        else
            KB_OPTIONS=$(kb_default_options "$KB_LAYOUT")
        fi
        KB_SOURCE="--keyboard"
        KB_VCONSOLE=$(kb_vconsole_for "${KB_LAYOUT%%,*}")
        return 0
    fi

    # 1. The layout the rice itself would load. Re-running the installer keeps your choice.
    if candidate=$(kb_lua_value "$lua" kb_layout) && [ -n "$candidate" ]; then
        if cleaned=$(kb_sanitize_list "$candidate"); then
            if opts=$(kb_lua_value "$lua" kb_options); then
                KB_OPTIONS=$opts
            else
                KB_OPTIONS=$(kb_default_options "$cleaned")
            fi
            kb_set "$cleaned" "$KB_OPTIONS" "user.lua"
            return 0
        fi
    fi

    # 2. A live Hyprland session. "us,ru" is the upstream default, not a user choice.
    if candidate=$(kb_from_hyprctl) && [ -n "$candidate" ] && [ "$candidate" != "us,ru" ]; then
        if cleaned=$(kb_sanitize_list "$candidate"); then
            kb_set "$cleaned" "$(kb_default_options "$cleaned")" "Hyprland (live)"
            return 0
        fi
    fi

    # 3. XKB_DEFAULT_LAYOUT, usually exported by the compositor.
    if [ -n "${XKB_DEFAULT_LAYOUT:-}" ] && [ "${XKB_DEFAULT_LAYOUT}" != "us,ru" ]; then
        if cleaned=$(kb_sanitize_list "$XKB_DEFAULT_LAYOUT"); then
            if [ "$cleaned" = us ]; then
                weak=us weak_src="XKB_DEFAULT_LAYOUT"
            else
                KB_OPTIONS=${XKB_DEFAULT_OPTIONS:-$(kb_default_options "$cleaned")}
                kb_set "$cleaned" "$KB_OPTIONS" "XKB_DEFAULT_LAYOUT"
                return 0
            fi
        fi
    fi

    # 4. localectl. A bare "us" with no 00-keyboard.conf is just the Arch default.
    if candidate=$(kb_localectl_field "X11 Layout") && [ -n "$candidate" ]; then
        if cleaned=$(kb_sanitize_list "$candidate"); then
            if [ "$cleaned" = us ] && [ ! -f /etc/X11/xorg.conf.d/00-keyboard.conf ]; then
                [ -n "$weak" ] || { weak=us; weak_src="localectl (default)"; }
            else
                opts=$(kb_localectl_field "X11 Options" || true)
                [ -n "$opts" ] || opts=$(kb_default_options "$cleaned")
                kb_set "$cleaned" "$opts" "localectl"
                return 0
            fi
        fi
    fi

    # 5. The Xorg keyboard file itself.
    if candidate=$(kb_x11_conf_layout) && [ -n "$candidate" ]; then
        if cleaned=$(kb_sanitize_list "$candidate"); then
            if [ "$cleaned" = us ]; then
                [ -n "$weak" ] || { weak=us; weak_src="00-keyboard.conf"; }
            else
                opts=$(kb_x11_conf_options || true)
                [ -n "$opts" ] || opts=$(kb_default_options "$cleaned")
                kb_set "$cleaned" "$opts" "00-keyboard.conf"
                return 0
            fi
        fi
    fi

    # 6. The console keymap, which is what the guide configures as la-latin1.
    if candidate=$(kb_vconsole_keymap) && [ -n "$candidate" ]; then
        if cleaned=$(kb_sanitize_list "$candidate"); then
            if [ "$cleaned" = us ]; then
                [ -n "$weak" ] || { weak=us; weak_src="/etc/vconsole.conf"; weak_vconsole=$candidate; }
            else
                kb_set "$cleaned" "$(kb_default_options "$cleaned")" "/etc/vconsole.conf" "$candidate"
                return 0
            fi
        fi
    fi

    # 7. setxkbmap (X11 or XWayland).
    if candidate=$(kb_from_setxkbmap) && [ -n "$candidate" ]; then
        case $candidate in
            "us,ru"|"us, ru") candidate= ;;
        esac
        if [ -n "$candidate" ] && cleaned=$(kb_sanitize_list "$candidate"); then
            if [ "$cleaned" != us ]; then
                kb_set "$cleaned" "$(kb_default_options "$cleaned")" "setxkbmap"
                return 0
            fi
            [ -n "$weak" ] || { weak=us; weak_src="setxkbmap"; }
        fi
    fi

    # 8. Debian's /etc/default/keyboard.
    if candidate=$(kb_from_default_keyboard) && [ -n "$candidate" ]; then
        if cleaned=$(kb_sanitize_list "$candidate"); then
            if [ "$cleaned" != us ]; then
                kb_set "$cleaned" "$(kb_default_options "$cleaned")" "/etc/default/keyboard"
                return 0
            fi
            [ -n "$weak" ] || { weak=us; weak_src="/etc/default/keyboard"; }
        fi
    fi

    # 9. The locale is the best hint on a fresh install where nothing keyboard-related exists yet.
    loc=$(kb_locale_name)
    candidate=$(kb_from_locale)
    if [ -n "$candidate" ] && [ "$candidate" != us ]; then
        kb_set "$candidate" "$(kb_default_options "$candidate")" "locale ${loc:-C}"
        return 0
    fi
    [ -n "$weak" ] || { weak=us; weak_src="locale ${loc:-C}"; }

    # 10. Nothing found.
    kb_set "$weak" "" "$weak_src" "${weak_vconsole:-}"
    if [ "$weak" = us ]; then
        warn "could not find a keyboard layout; using 'us'. Override with --keyboard latam"
    fi
}

kb_confirm() {
    [ "${YES:-0}" = 1 ] && return 0
    [ "${MODE:-full}" = check ] && return 0
    [ -t 0 ] || return 0
    if confirm "Keyboard: $KB_LAYOUT (from $KB_SOURCE). Use it?" y; then
        return 0
    fi
    ask "XKB layout (comma-separated for several)" "$KB_LAYOUT"
    KB_LAYOUT=$(kb_sanitize_list "$REPLY") || die "invalid layout: $REPLY"
    ask "XKB options (none to clear)" "${KB_OPTIONS:-none}"
    case $REPLY in
        ""|none|None|NONE) KB_OPTIONS= ;;
        *) KB_OPTIONS=$REPLY ;;
    esac
    [ -n "$KB_OPTIONS" ] || KB_OPTIONS=$(kb_default_options "$KB_LAYOUT")
    KB_SOURCE="answered by you"
    KB_VCONSOLE=$(kb_vconsole_for "${KB_LAYOUT%%,*}")
}

kb_report() {
    say "keyboard"
    info "layout:  $KB_LAYOUT"
    info "options: ${KB_OPTIONS:-(none)}"
    info "console: $KB_VCONSOLE"
    info "source:  $KB_SOURCE"
    case $KB_LAYOUT in
        latam) dim "Spanish (Latin America)" ;;
        es)    dim "Spanish (Spain)" ;;
        us)    dim "English (US)" ;;
    esac
    if [ -n "$KB_OPTIONS" ]; then
        dim "switch layouts with Alt+Shift (grp:alt_shift_toggle)"
    fi
}

kb_apply_user_lua() { # file
    local file=$1 content
    mkdir -p -- "$(dirname -- "$file")"
    if [ ! -f "$file" ]; then
        # presérvalo si el instalador acaba de mover el ~/.config/hypr anterior al backup
        if [ -n "${BACKUP:-}" ] && [ -f "$BACKUP/.config/hypr/user.lua" ]; then
            cp -- "$BACKUP/.config/hypr/user.lua" "$file"
        elif [ -f "$DOTS/config/hypr/user.lua.example" ]; then
            cp -- "$DOTS/config/hypr/user.lua.example" "$file"
        else
            printf '%s\n' '-- Glyph overrides. Generated by install.sh; gitignored.' >"$file"
        fi
    fi
    content="hl.config({
    input = {
        kb_layout = \"$(lua_escape "$KB_LAYOUT")\",
        kb_options = \"$(lua_escape "$KB_OPTIONS")\",
    },
})"
    replace_block "$file" "-- >>> glyph:keyboard" "-- <<< glyph:keyboard" "$content"
    chmod 644 "$file" 2>/dev/null || true
    ok "user.lua: kb_layout = \"$KB_LAYOUT\"${KB_OPTIONS:+, kb_options = \"$KB_OPTIONS\"}"
}

kb_write_x11_conf() { # layout options
    local layout=$1 options=$2 f=/etc/X11/xorg.conf.d/00-keyboard.conf
    if [ -f "$f" ] && grep -q 'XkbLayout' "$f"; then
        sudo sed -i -E "s|(Option[[:space:]]+\"XkbLayout\"[[:space:]]+\")[^\"]*(\")|\1${layout}\2|" "$f"
        if grep -q 'XkbOptions' "$f"; then
            sudo sed -i -E "s|(Option[[:space:]]+\"XkbOptions\"[[:space:]]+\")[^\"]*(\")|\1${options}\2|" "$f"
        elif [ -n "$options" ]; then
            sudo sed -i -E "/^[[:space:]]*EndSection/i\\    Option \"XkbOptions\" \"${options}\"" "$f"
        fi
    elif [ -f "$f" ]; then
        # Someone else's file without XkbLayout: append our InputClass, do not overwrite theirs.
        printf '%s\n' \
            'Section "InputClass"' \
            '    Identifier "glyph-keyboard"' \
            '    MatchIsKeyboard "on"' \
            "    Option \"XkbLayout\" \"$layout\"" \
            "    Option \"XkbOptions\" \"$options\"" \
            'EndSection' | sudo tee -a "$f" >/dev/null
    else
        sudo mkdir -p -- "$(dirname -- "$f")"
        printf '%s\n' \
            'Section "InputClass"' \
            '    Identifier "system-keyboard"' \
            '    MatchIsKeyboard "on"' \
            "    Option \"XkbLayout\" \"$layout\"" \
            "    Option \"XkbOptions\" \"$options\"" \
            'EndSection' | sudo tee "$f" >/dev/null
    fi
}

kb_apply_system() { # no_system_keyboard
    local no_system=${1:-0} did_vc=0 did_x11=0
    if [ "$no_system" = 1 ]; then
        info "system keyboard: skipped (--no-system-keyboard)"
        return 0
    fi
    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "[dry-run] would set console keymap to $KB_VCONSOLE and X11 layout to $KB_LAYOUT"
        return 0
    fi

    # Keep the first copy: a second install must not replace our restore point with a
    # file that Glyph itself already modified, or uninstall would not restore the original.
    backup_file /etc/vconsole.conf 1 1
    backup_file /etc/X11/xorg.conf.d/00-keyboard.conf 1 1

    if have localectl && [ -d /run/systemd/system ]; then
        if sudo localectl set-keymap --no-convert "$KB_VCONSOLE"; then
            did_vc=1
            ok "console keymap: $KB_VCONSOLE"
        else
            warn "localectl set-keymap failed; writing /etc/vconsole.conf directly"
        fi
        if [ -n "$KB_OPTIONS" ]; then
            if sudo localectl set-x11-keymap --no-convert "$KB_LAYOUT" "" "" "$KB_OPTIONS"; then
                did_x11=1
                ok "X11 layout: $KB_LAYOUT ($KB_OPTIONS)"
            else
                warn "localectl set-x11-keymap failed; writing 00-keyboard.conf directly"
            fi
        else
            if sudo localectl set-x11-keymap --no-convert "$KB_LAYOUT"; then
                did_x11=1
                ok "X11 layout: $KB_LAYOUT"
            else
                warn "localectl set-x11-keymap failed; writing 00-keyboard.conf directly"
            fi
        fi
    fi

    if [ "$did_vc" = 0 ]; then
        set_kv_file /etc/vconsole.conf KEYMAP "$KB_VCONSOLE" 1
        ok "console keymap: $KB_VCONSOLE (/etc/vconsole.conf)"
    fi
    if [ "$did_x11" = 0 ]; then
        kb_write_x11_conf "$KB_LAYOUT" "$KB_OPTIONS"
        ok "X11 layout: $KB_LAYOUT (/etc/X11/xorg.conf.d/00-keyboard.conf)"
    fi

    info "SDDM/LightDM (X11 greeter) and the TTYs now match the rice"
    dim "re-login for X11; Hyprland picks it up with hyprctl reload"
}
