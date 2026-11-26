#!/usr/bin/env bash
# Glyph: shared helpers for install.sh and uninstall.sh.
# Sourced, never executed directly.

# --- output -----------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RED=$'\e[38;2;215;25;33m'
    C_YELLOW=$'\e[38;2;230;180;60m'
    C_GREEN=$'\e[38;2;120;190;120m'
    C_DIM=$'\e[2m'
    C_RESET=$'\e[0m'
else
    C_RED='' C_YELLOW='' C_GREEN='' C_DIM='' C_RESET=''
fi

say()  { printf '%s●%s %s\n' "$C_RED" "$C_RESET" "$*"; }
step() { printf '\n%s●%s %s\n' "$C_RED" "$C_RESET" "$*"; }
info() { printf '  %s\n' "$*"; }
dim()  { printf '  %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
ok()   { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# --- input ------------------------------------------------------------------
confirm() { # question [y|n] -> 0 yes, 1 no; --yes answers yes
    local prompt=$1 default=${2:-y} ans
    if [ "${YES:-0}" = 1 ]; then return 0; fi
    if [ ! -t 0 ]; then return 1; fi
    case $default in
        y|Y) prompt="$prompt [Y/n] " ;;
        *)   prompt="$prompt [y/N] " ;;
    esac
    printf '  %s' "$prompt"
    read -r ans || ans=
    ans=${ans:-$default}
    case $ans in
        y|Y|yes|YES|s|S|si|sí|SI) return 0 ;;
        *) return 1 ;;
    esac
}

ask() { # prompt [default] -> REPLY
    local prompt=$1 default=${2:-}
    if [ ! -t 0 ]; then REPLY=$default; return 0; fi
    if [ -n "$default" ]; then
        printf '  %s [%s]: ' "$prompt" "$default"
    else
        printf '  %s: ' "$prompt"
    fi
    read -r REPLY || REPLY=$default
    REPLY=${REPLY:-$default}
}

# --- shell ------------------------------------------------------------------
run() {
    if [ "${DRY_RUN:-0}" = 1 ]; then
        printf '  %s[dry-run]%s %s\n' "$C_DIM" "$C_RESET" "$*"
        return 0
    fi
    "$@"
}

have() { command -v "$1" >/dev/null 2>&1; }

version_ge() { # have need -> 0 if have >= need
    local have_v=${1:-0} need_v=${2:-0}
    [ "$(printf '%s\n%s\n' "$need_v" "$have_v" | sort -V | head -n 1)" = "$need_v" ]
}

version_num() { # first x.y[.z] in a string
    grep -oE '[0-9]+(\.[0-9]+)+' <<<"${1-}" 2>/dev/null | head -n 1 || true
}

trim() {
    local s=${1-}
    s=${s#"${s%%[![:space:]]*}"}
    s=${s%"${s##*[![:space:]]}"}
    printf '%s' "$s"
}

unquote() {
    local s
    s=$(trim "${1-}")
    case $s in
        \"*\") s=${s#\"}; s=${s%\"} ;;
        \'*\') s=${s#\'}; s=${s%\'} ;;
    esac
    printf '%s' "$s"
}

lua_escape() {
    printf '%s' "${1-}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# --- files ------------------------------------------------------------------
replace_block() { # file start end content (content is written verbatim)
    local file=$1 start=$2 end=$3 content=$4
    local tmp block
    tmp=$(mktemp) || die "mktemp failed"
    block=$(mktemp) || die "mktemp failed"
    printf '%s\n' "$content" >"$block"

    if [ -f "$file" ] && grep -qxF -- "$start" "$file" && grep -qxF -- "$end" "$file"; then
        # Replace only the managed block. Everything outside it is preserved.
        awk -v s="$start" -v e="$end" -v b="$block" '
            $0 == s {
                print
                while ((getline line < b) > 0) print line
                close(b)
                skip = 1
                next
            }
            $0 == e { skip = 0; print; next }
            !skip { print }
        ' "$file" >"$tmp"
    else
        if [ -f "$file" ] && [ -s "$file" ]; then
            cat "$file" >"$tmp"
        else
            : >"$tmp"
        fi
        if [ -s "$tmp" ]; then printf '\n' >>"$tmp"; fi
        {
            printf '%s\n' "$start"
            printf '%s\n' "$content"
            printf '%s\n' "$end"
        } >>"$tmp"
    fi

    cat "$tmp" >"$file"
    rm -f -- "$tmp" "$block"
}

backup_file() { # path [use_sudo:0|1] [keep_first:0|1]
    local path=$1 use_sudo=${2:-0} keep_first=${3:-0} dest b
    [ -e "$path" ] || [ -L "$path" ] || return 0
    # keep_first=1: never replace the pre-Glyph copy with a later, already-modified one.
    if [ "$keep_first" = 1 ]; then
        for b in "$path".glyph-backup-*; do
            if [ -e "$b" ] || [ -L "$b" ]; then
                info "original backup already kept: $b"
                return 0
            fi
        done
    fi
    dest="${path}.glyph-backup-${GLYPH_STAMP:-$(date +%F_%H-%M-%S)}"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        info "backup already exists: $dest"
        return 0
    fi
    if [ "$use_sudo" = 1 ]; then
        sudo cp -a -- "$path" "$dest" || die "cannot back up $path"
    else
        cp -a -- "$path" "$dest" || die "cannot back up $path"
    fi
    info "backup: $dest"
}

set_kv_file() { # file key value [use_sudo]
    local file=$1 key=$2 value=$3 use_sudo=${4:-0} tmp
    tmp=$(mktemp) || die "mktemp failed"
    if [ -f "$file" ]; then
        awk -v k="$key" -v v="$value" '
            BEGIN { done = 0 }
            $0 ~ "^[[:space:]]*" k "=" {
                if (!done) { print k "=" v; done = 1 }
                next
            }
            { print }
            END { if (!done) print k "=" v }
        ' "$file" >"$tmp"
    else
        printf '%s=%s\n' "$key" "$value" >"$tmp"
    fi
    if [ "$use_sudo" = 1 ]; then
        # shellcheck disable=SC2024 # the input redirect is read by the user's shell; tee runs as root
        sudo tee "$file" <"$tmp" >/dev/null
    else
        cat "$tmp" >"$file"
    fi
    rm -f -- "$tmp"
}

is_repo_link() { # path -> 0 if it is a symlink into $DOTS
    local link=$1 target
    [ -L "$link" ] || return 1
    target=$(readlink -- "$link" 2>/dev/null || true)
    case $target in
        "$DOTS"|"$DOTS"/*) return 0 ;;
    esac
    target=$(readlink -f -- "$link" 2>/dev/null || true)
    case $target in
        "$DOTS"|"$DOTS"/*) return 0 ;;
    esac
    return 1
}

# --- system -----------------------------------------------------------------
is_arch() { have pacman && { [ -f /etc/arch-release ] || have pacman; }; }

pkg_installed() { pacman -Q "$1" >/dev/null 2>&1; }

pkg_version() { pacman -Q "$1" 2>/dev/null | awk '{print $2}'; }

aur_helper() {
    if have yay; then printf 'yay'; return 0; fi
    if have paru; then printf 'paru'; return 0; fi
    return 1
}

sudo_start() {
    [ "${DRY_RUN:-0}" = 1 ] && return 0
    have sudo || die "sudo is required"
    sudo -v || die "sudo authentication failed"
    ( while true; do sleep 60; sudo -n true 2>/dev/null || exit; done ) &
    SUDO_KEEPALIVE_PID=$!
    # shellcheck disable=SC2064
    trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
}

sudo_stop() {
    [ -n "${SUDO_KEEPALIVE_PID:-}" ] || return 0
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    unset SUDO_KEEPALIVE_PID
    trap - EXIT
}
