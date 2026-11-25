#!/usr/bin/env bash
# Glyph: monitor discovery and optional Hyprland monitor rules.
#
# Glyph already asks Hyprland for "highres/auto", so a normal DDC/EDID monitor needs no help.
# This module reports what the kernel sees, warns when a connected output has no modes (the usual
# symptom of a DVI->VGA adapter that eats EDID), and writes explicit hl.monitor() rules into
# hypr/user.lua when you pass --monitor OUTPUT:MODE[:POSITION[:SCALE]].

declare -a MON_RULES=()
declare -a MON_OUTPUTS=()
declare -a MON_NO_EDID=()
declare -A MON_MODE=()
declare -A MON_EDID=()
declare -A MON_ENABLED=()

mon_detect() {
    MON_OUTPUTS=()
    MON_NO_EDID=()
    MON_MODE=()
    MON_EDID=()
    MON_ENABLED=()

    local d base name status mode edid enabled
    [ -d /sys/class/drm ] || return 0
    for d in /sys/class/drm/card*-*; do
        [ -d "$d" ] || continue
        base=${d##*/}
        name=${base#card*-}
        case $name in
            Writeback-*|"$base") continue ;;
        esac
        status=$(cat "$d/status" 2>/dev/null || printf 'unknown')
        [ "$status" = connected ] || continue
        mode=$(head -n 1 "$d/modes" 2>/dev/null || true)
        edid=no
        [ -s "$d/edid" ] && edid=yes
        enabled=$(cat "$d/enabled" 2>/dev/null || printf 'unknown')
        MON_OUTPUTS+=("$name")
        MON_MODE["$name"]=$mode
        MON_EDID["$name"]=$edid
        MON_ENABLED["$name"]=$enabled
        [ -n "$mode" ] || MON_NO_EDID+=("$name")
    done
}

mon_report() {
    say "monitors"
    if [ ${#MON_OUTPUTS[@]} -eq 0 ]; then
        warn "no connected DRM outputs found (VM, headless or a non-Linux system)"
        return 0
    fi
    local out mode edid enabled
    for out in "${MON_OUTPUTS[@]}"; do
        mode=${MON_MODE[$out]:-}
        edid=${MON_EDID[$out]:-no}
        enabled=${MON_ENABLED[$out]:-unknown}
        if [ -n "$mode" ]; then
            info "$out: $mode (EDID: $edid, $enabled)"
        else
            warn "$out: connected but no modes reported (EDID: $edid, $enabled)"
        fi
    done
    if have hyprctl && have jq && hyprctl monitors -j >/dev/null 2>&1; then
        info "Hyprland is using:"
        hyprctl monitors -j 2>/dev/null |
            jq -r '.[] | "  \(.name): \(.width)x\(.height)@\(.refreshRate) at \(.x),\(.y), scale \(.scale)"' 2>/dev/null ||
            true
    fi
}

mon_add_rule() { # OUTPUT:MODE[:POSITION[:SCALE]]
    local spec=${1-} out mode pos scale rest
    case $spec in
        *:*:*) : ;;
        *:*) : ;;
        *) die "--monitor needs OUTPUT:MODE, e.g. --monitor DVI-I-1:1366x768@60" ;;
    esac
    out=${spec%%:*}
    rest=${spec#*:}
    mode=${rest%%:*}
    if [ "$rest" = "$mode" ]; then
        pos=auto
        scale=auto
    else
        rest=${rest#*:}
        pos=${rest%%:*}
        if [ "$rest" = "$pos" ]; then
            scale=auto
        else
            scale=${rest#*:}
        fi
    fi
    [ -n "$out" ] || die "--monitor: the output name is empty"
    [ -n "$mode" ] || die "--monitor: the mode is empty"
    pos=${pos:-auto}
    scale=${scale:-auto}
    case $mode in
        [0-9]*x[0-9]*) : ;;
        *) warn "mode '$mode' does not look like WIDTHxHEIGHT[@REFRESH]" ;;
    esac
    MON_RULES+=("$out|$mode|$pos|$scale")
}

mon_validate_rules() {
    [ ${#MON_RULES[@]} -eq 0 ] && return 0
    [ ${#MON_OUTPUTS[@]} -eq 0 ] && return 0
    local rule out o found
    for rule in "${MON_RULES[@]}"; do
        out=${rule%%|*}
        found=0
        for o in "${MON_OUTPUTS[@]}"; do
            [ "$o" = "$out" ] && found=1
        done
        if [ "$found" = 0 ]; then
            warn "monitor '$out' is not connected (connected: ${MON_OUTPUTS[*]})"
        fi
    done
}

mon_prompt() {
    [ ${#MON_NO_EDID[@]} -eq 0 ] && return 0
    [ "${YES:-0}" = 1 ] && return 0
    [ -t 0 ] || return 0
    local out=${MON_NO_EDID[0]}
    if confirm "$out reports no modes (EDID/DDC failed). Do you know its resolution?" n; then
        ask "Mode for $out (WIDTHxHEIGHT[@REFRESH], empty to skip)" ""
        [ -n "$REPLY" ] && mon_add_rule "$out:$REPLY"
    fi
}

mon_apply_user_lua() { # file
    local file=$1 content='' rule out mode pos scale
    [ ${#MON_RULES[@]} -gt 0 ] || return 0
    for rule in "${MON_RULES[@]}"; do
        IFS='|' read -r out mode pos scale <<<"$rule"
        content+="hl.monitor({ output = \"$(lua_escape "$out")\", mode = \"$(lua_escape "$mode")\", position = \"$(lua_escape "$pos")\", scale = \"$(lua_escape "$scale")\" })"$'\n'
    done
    content=${content%$'\n'}
    replace_block "$file" "-- >>> glyph:monitor" "-- <<< glyph:monitor" "$content"
    ok "user.lua: ${#MON_RULES[@]} monitor rule(s)"
}

mon_suggest() {
    [ ${#MON_NO_EDID[@]} -eq 0 ] && return 0
    local out=${MON_NO_EDID[0]}
    warn "no EDID/modes on: ${MON_NO_EDID[*]}"
    info "if the picture is wrong, force the mode it should use:"
    dim "./install.sh --monitor ${out}:WIDTHxHEIGHT@REFRESH"
}
