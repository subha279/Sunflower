#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Single entry point: install, update, rebuild, validate,
# maintenance, rollback and system recovery.
# ============================================================

VERSION="2.0"

# The repository root is derived from the script's own location, symlink
# included -- never from pwd. The user may run /anywhere/setup.sh from /,
# from the home directory, from /tmp or from the ISO's own /iso, with a
# checkout directory named anything, in a path containing spaces, and from
# an archive that never had a .git directory at all.
_here="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1; then
    _resolved="$(readlink -f -- "$_here" 2>/dev/null || true)"
    if [[ -n "$_resolved" ]]; then _here="$_resolved"; fi
    unset _resolved
fi
ROOT="$(cd -- "$(dirname -- "$_here")" && pwd)"
unset _here
VARS="$ROOT/lib/variables.nix"

# The command line as first seen. ci_require_root re-executes the script
# through a passwordless sudo when needed and has to reproduce it exactly,
# including the "you came from the menu, land me in the installer" case.
SETUP_ARGS=("$@")

# Flakes are not enabled by default everywhere this runs -- most importantly
# on the live installer ISO, where `nix flake check` from the menu and every
# nix invocation inside nixos-install/nixos-enter would otherwise fail.
# NIX_CONFIG reaches the whole process tree (those tools shell out to nix
# themselves), and it is APPENDED so any settings already in the environment
# -- substituters, access tokens, whatever the session exported -- survive,
# while this line comes last and therefore decides experimental-features.
export NIX_CONFIG="${NIX_CONFIG:+$NIX_CONFIG$'\n'}experimental-features = nix-command flakes"

# The flake exposes exactly one system: nixosConfigurations.sunflower, fed
# by ./hosts/sunflower. Everything that names a system or a host directory
# derives from these two values, so a rename is one line, not twenty.
FLAKE_HOST="sunflower"
HOST_DIR="hosts/$FLAKE_HOST"
FLAKE_TARGET="$ROOT#$FLAKE_HOST"
REPO_NAME="Sunflower"
REPO_URL="https://github.com/subha279/Sunflower.git"

# ============================================================
# PRESENTATION LAYER
#
# One vocabulary for everything this script prints. The names
# below -- info / success / warning / error / run_cmd / section /
# pause / confirm, plus v_ok / v_fail / v_info for the validator's
# aligned results -- are the whole set. There used to be three
# parallel copies of this: these, an m_* family for the maintenance
# dashboard, and a v_* family nested inside the validator. They are
# now one implementation.
#
# The colour variables keep their old names (RED, CYAN, ...) on
# purpose. Around a hundred printf call sites in the maintenance
# and validator sections reference them directly, so re-pointing
# the values at the live theme upgrades all of them without
# touching any of them.
# ============================================================

# Terminal capabilities
#
# None of this was detected before: the script emitted escape codes
# unconditionally, so `./setup.sh check | tee log` wrote escape
# sequences into the file and NO_COLOR was ignored.

if [[ -t 1 ]]; then IS_TTY=1; else IS_TTY=0; fi

# Colour is off when asked for (NO_COLOR), when the terminal says it
# cannot render it (TERM=dumb), or when stdout is not a terminal at all.
#
# Only an *explicit* TERM=dumb disables it. An unset TERM alongside a real
# tty means a stripped environment rather than a teletype, and every
# terminal emulator that can give us a tty can also handle basic ANSI --
# the -t 1 test above is what actually protects pipes and log files.
UI_COLOR=1
if [[ -n "${NO_COLOR:-}" ]]; then UI_COLOR=0; fi
if [[ "${TERM:-}" == "dumb" ]]; then UI_COLOR=0; fi
if [[ "$IS_TTY" -eq 0 ]]; then UI_COLOR=0; fi

# 24-bit colour is what lets the palette be the actual theme rather
# than an approximation of it. Without it we fall back to the 3-bit
# codes this script used to hardcode.
#
# COLORTERM is the reliable signal and kitty sets it, but it is lost
# across sudo and some multiplexers, so a TERM that advertises direct
# or 256 colour counts too.
UI_TRUECOLOR=0
if [[ "$UI_COLOR" -eq 1 ]]; then
    case "${COLORTERM:-}" in
    truecolor | 24bit) UI_TRUECOLOR=1 ;;
    esac

    case "${TERM:-}" in
    *-direct* | *-256color | kitty | xterm-kitty | alacritty | foot | wezterm)
        UI_TRUECOLOR=1
        ;;
    esac
fi

# Box drawing and the nicer glyphs need a UTF-8 locale.
#
# Also dropped without a tty. Strictly, UTF-8 keeps working through a
# pipe -- but validator output gets redirected into logs, pasted into
# issues and mailed around, and ASCII survives all of those intact.
UI_UNICODE=1
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
*UTF-8* | *utf-8* | *UTF8* | *utf8*) ;;
*) UI_UNICODE=0 ;;
esac
if [[ "${TERM:-}" == "dumb" ]]; then UI_UNICODE=0; fi
if [[ "$IS_TTY" -eq 0 ]]; then UI_UNICODE=0; fi

# Width for the panel frame and the section rules. Clamped: a rule
# stretched across a 210-column terminal reads as a divider in a
# spreadsheet, not a heading.
UI_WIDTH=64
if [[ "$IS_TTY" -eq 1 ]]; then
    UI_WIDTH="$(tput cols 2>/dev/null || printf '64')"
    if [[ "$UI_WIDTH" -gt 74 ]]; then UI_WIDTH=74; fi
    if [[ "$UI_WIDTH" -lt 40 ]]; then UI_WIDTH=40; fi
fi

# Palette, read from the live Sunflower theme
#
# ~/.config/sunflower/active-theme and themes/<id>.json are the same
# files core/Theme.qml watches, so the installer wears whatever
# colourscheme the desktop is currently wearing. Strictly read-only:
# this participates in no part of the theme pipeline, it only looks
# at the output. Every lookup carries the built-in sunflower value as a
# fallback, so a missing or half-written file costs nothing.

SUNFLOWER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/sunflower"
UI_THEME_FILE=""

if [[ -r "$SUNFLOWER_DIR/active-theme" ]]; then
    UI_THEME_ID="$(tr -d '[:space:]' <"$SUNFLOWER_DIR/active-theme" 2>/dev/null || printf '')"

    if [[ -n "$UI_THEME_ID" && -r "$SUNFLOWER_DIR/themes/$UI_THEME_ID.json" ]]; then
        UI_THEME_FILE="$SUNFLOWER_DIR/themes/$UI_THEME_ID.json"
    fi
fi

# Pull one "key":"#rrggbb" pair out of the theme JSON. Deliberately
# grep rather than jq: jq is not guaranteed present on a machine that
# is still being installed, and this needs exactly one field.
ui_hex() {
    local key="$1" fallback="$2" hex=""

    if [[ -n "$UI_THEME_FILE" ]]; then
        hex="$(grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"#[0-9a-fA-F]\{6\}\"" "$UI_THEME_FILE" 2>/dev/null |
            head -1 | grep -o '#[0-9a-fA-F]\{6\}' || printf '')"
    fi

    printf '%s' "${hex:-$fallback}"
}

# $1 theme key, $2 fallback hex, $3 basic ANSI code for 16-colour terminals
ui_fg() {
    local hex

    if [[ "$UI_COLOR" -eq 0 ]]; then
        printf ''
        return 0
    fi

    if [[ "$UI_TRUECOLOR" -eq 1 ]]; then
        hex="$(ui_hex "$1" "$2")"

        printf '\033[38;2;%d;%d;%dm' \
            "$((16#${hex:1:2}))" "$((16#${hex:3:2}))" "$((16#${hex:5:2}))"

        return 0
    fi

    printf '\033[%sm' "$3"
}

# Real escape bytes ($'...'), not literal backslash text. Every call site
# prints these through %b, which happens to interpret \033, but anything
# that uses %s or echo would have shown the raw text instead of resetting
# the colour. RED/GREEN/... below are already real bytes from ui_fg; these
# two now match them.
if [[ "$UI_COLOR" -eq 1 ]]; then
    RESET=$'\033[0m'
    BOLD=$'\033[1m'
else
    RESET=''
    BOLD=''
fi

# Semantic, not literal. The names are historical; the theme role in
# the trailing comment is what each one actually means.
RED="$(ui_fg error '#F38BA8' 31)"               # failure
GREEN="$(ui_fg success '#A6E3A1' 32)"           # success
YELLOW="$(ui_fg warning '#F9E2AF' 33)"          # warning
BLUE="$(ui_fg info '#89B4FA' 34)"               # information
MAGENTA="$(ui_fg terminalMagenta '#F5C2E7' 35)" # a command about to run
CYAN="$(ui_fg accent '#CBA6F7' 36)"             # chrome: headings, numbers, frames
DIM="$(ui_fg textMuted '#989CAC' 2)"            # de-emphasised

# Glyphs
#
# These literals are the Unicode / Nerd Font set. The block just below
# them swaps in ASCII when the locale cannot render it, so nothing here
# needs a conditional of its own.

ICON_OK="✓"
ICON_FAIL="✗"
ICON_WARN="!"
ICON_INFO="ℹ"
ICON_ARROW="→"

UI_TL="╭"
UI_TR="╮"
UI_BL="╰"
UI_BR="╯"
UI_H="─"
UI_V="│"
UI_RULE="─"

UI_SPIN=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

# ASCII fallback, for a terminal without a UTF-8 locale. Everything
# above is replaced wholesale rather than conditionally, so the rest of
# the script only ever refers to the names.
if [[ "$UI_UNICODE" -eq 0 ]]; then
    ICON_OK="ok"
    ICON_FAIL="x"
    ICON_WARN="!"
    ICON_INFO="i"
    ICON_ARROW=">"

    UI_TL="+"
    UI_TR="+"
    UI_BL="+"
    UI_BR="+"
    UI_H="-"
    UI_V="|"
    UI_RULE="-"

    UI_SPIN=("|" "/" "-" "\\")
fi

# Cursor
#
# The trap lives here rather than three hundred lines further down next
# to the maintenance dashboard, because a Ctrl-C anywhere in the script
# has to put the cursor back.

hide_cursor() {
    if [[ "$IS_TTY" -eq 1 ]]; then tput civis 2>/dev/null || true; fi
}

show_cursor() {
    if [[ "$IS_TTY" -eq 1 ]]; then tput cnorm 2>/dev/null || true; fi
}

# Exit / signal handling.
#
# EXIT is the one cleanup path: restore the cursor, detach any swap the
# installer attached to the target, and take the temporary build directory
# off the target with it. INT/TERM/HUP route through exit() so the EXIT
# trap always runs -- the old `trap show_cursor EXIT INT TERM` restored the
# cursor and then let the script carry on as if nothing happened.
#
# ci_teardown_swap is defined much later; the script can die before it
# exists, hence the declare -F guard.
on_exit() {
    show_cursor
    if declare -F ci_teardown_swap >/dev/null 2>&1; then
        ci_teardown_swap || true
    fi
    if declare -F ci_cleanup_build_dirs >/dev/null 2>&1; then
        ci_cleanup_build_dirs || true
    fi
}

on_signal() {
    printf '\n'
    warning "Interrupted."
    exit 130
}

trap on_exit EXIT
trap on_signal INT TERM HUP

# Primitives

# Repeat $1 exactly $2 times.
ui_repeat() {
    local char="$1" count="$2" out="" i

    for ((i = 0; i < count; i++)); do out+="$char"; done

    printf '%s' "$out"
}

# Length of a string with escape sequences discounted, so the panel
# border lines up whether or not colour is on.
ui_visible_len() {
    local stripped

    stripped="$(printf '%b' "$1" | sed -e 's/\x1b\[[0-9;]*m//g')"

    printf '%s' "${#stripped}"
}

clear_screen() {
    if [[ "$IS_TTY" -eq 1 ]]; then clear 2>/dev/null || printf '\033[H\033[2J'; fi
}

hr() {
    printf '  %b%s%b\n' "$DIM" "$(ui_repeat "$UI_RULE" "$((UI_WIDTH - 2))")" "$RESET"
}

# Log lines
#
# Two leading spaces, a coloured glyph, then the message -- the shape
# this script has always had, so nothing downstream needs re-reading.

die() {
    printf '  %b%s%b %s\n' "$RED" "$ICON_FAIL" "$RESET" "$*" >&2
    exit 1
}
info() { printf '  %b%s%b %s\n' "$BLUE" "$ICON_INFO" "$RESET" "$*"; }
success() { printf '  %b%s%b %s\n' "$GREEN" "$ICON_OK" "$RESET" "$*"; }
warning() { printf '  %b%s%b %s\n' "$YELLOW" "$ICON_WARN" "$RESET" "$*"; }
error() { printf '  %b%s%b %s\n' "$RED" "$ICON_FAIL" "$RESET" "$*" >&2; }
run_cmd() { printf '  %b%s%b %b%s%b\n' "$MAGENTA" "$ICON_ARROW" "$RESET" "$DIM" "$*" "$RESET"; }

section() {
    printf '\n  %b%b%s%b\n' "$CYAN" "$BOLD" "$1" "$RESET"
    hr
}

pause() {
    echo
    read -r -p "  Press Enter to continue..." _ || true
}

confirm() {
    local prompt="${1:-Continue?}" answer
    echo
    read -r -p "  $prompt [y/N]: " answer
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# Validator results
#
# A distinct shape from the log lines above: a check result, not an
# event. These used to be function-local copies scattered across the
# old in-script validator and the verifier functions; they are one
# shared implementation now, used by the install verifiers
# (ci_check_variables, ci_verify_hardware, ci_final_verify, ...).

V_FAILED=0

v_ok() { printf '  %b%s%b %s\n' "$GREEN" "$ICON_OK" "$RESET" "$1"; }

v_fail() {
    printf '  %b%s%b %s\n' "$RED" "$ICON_FAIL" "$RESET" "$1"
    V_FAILED=1
}

v_info() { printf '  %b%s%b %s\n' "$YELLOW" "$ICON_WARN" "$RESET" "$1"; }

v_separator() { hr; }

# Panel
#
# The framed header. $1 is the title, $2 an optional right-aligned tag
# (the version), and any further arguments become dimmed fact lines
# inside the frame.

panel() {
    local title="$1" tag="${2:-}"
    shift || true
    shift || true

    local inner=$((UI_WIDTH - 2))
    local head=" $title " tail="" pad

    if [[ -n "$tag" ]]; then tail=" $tag "; fi

    pad=$((inner - ${#head} - ${#tail} - 1))
    if [[ "$pad" -lt 1 ]]; then pad=1; fi

    printf '%b%s%s%b%s%b%s%s%s%b\n' \
        "$CYAN" "$UI_TL" "$UI_H" \
        "$BOLD" "$head" "$RESET$CYAN" \
        "$(ui_repeat "$UI_H" "$pad")" "$tail" "$UI_TR" "$RESET"

    local line len
    for line in "$@"; do
        len="$(ui_visible_len "$line")"

        pad=$((inner - len - 2))
        if [[ "$pad" -lt 0 ]]; then pad=0; fi

        printf '%b%s%b %b%s%b%s %b%s%b\n' \
            "$CYAN" "$UI_V" "$RESET" \
            "$DIM" "$line" "$RESET" "$(ui_repeat ' ' "$pad")" \
            "$CYAN" "$UI_V" "$RESET"
    done

    printf '%b%s%s%s%b\n' \
        "$CYAN" "$UI_BL" "$(ui_repeat "$UI_H" "$inner")" "$UI_BR" "$RESET"
}

# Verdict
#
# The framed one-line result the validator ends on. Same framing as
# panel() but tinted by outcome and centred, and it respects UI_WIDTH and
# UI_UNICODE rather than the fixed 62-column unicode box it replaces --
# which used to survive `| cat` as raw box characters.

verdict() {
    local tint="$1" icon="$2" msg="$3"

    local inner=$((UI_WIDTH - 2))
    local body="$icon  $msg"
    local len=${#body}

    if [[ "$len" -gt "$inner" ]]; then
        body="${body:0:$inner}"
        len="$inner"
    fi

    local left=$(((inner - len) / 2))
    local right=$((inner - len - left))

    local rule
    rule="$(ui_repeat "$UI_H" "$inner")"

    printf '%b%s%s%s%b\n' "$tint" "$UI_TL" "$rule" "$UI_TR" "$RESET"

    printf '%b%s%b%s%b%s%b%s%b%s%b\n' \
        "$tint" "$UI_V" "$RESET" \
        "$(ui_repeat ' ' "$left")" \
        "$tint$BOLD" "$body" "$RESET" \
        "$(ui_repeat ' ' "$right")" \
        "$tint" "$UI_V" "$RESET"

    printf '%b%s%s%s%b\n' "$tint" "$UI_BL" "$rule" "$UI_BR" "$RESET"
}

# Spinner
#
# Wraps a long operation whose output we do not need to watch, showing
# an elapsed second count so that a slow `nix flake check` never looks
# hung. Operations whose output IS the point -- nixos-rebuild switch
# above all -- are deliberately left streaming to the terminal.
#
# Without a TTY it degrades to plain lines, so piped output stays
# readable and no escape sequences leak into a log file. On failure the
# captured output is replayed to stderr, so nothing is ever swallowed.

spinner() {
    local label="$1"
    shift

    local log rc=0
    log="$(mktemp)"

    if [[ "$IS_TTY" -eq 0 ]]; then
        run_cmd "$label"

        if "$@" >"$log" 2>&1; then
            success "$label"
        else
            rc=$?
            error "$label"
            cat "$log" >&2
        fi

        rm -f "$log"
        return "$rc"
    fi

    "$@" >"$log" 2>&1 &
    local pid=$!
    local frame=0 start=$SECONDS

    hide_cursor

    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %b%s%b %s %b%ds%b' \
            "$CYAN" "${UI_SPIN[$frame]}" "$RESET" \
            "$label" "$DIM" "$((SECONDS - start))" "$RESET"

        frame=$(((frame + 1) % ${#UI_SPIN[@]}))
        sleep 0.08
    done

    wait "$pid" || rc=$?

    show_cursor

    # Erase the spinner line before the result replaces it.
    printf '\r\033[2K'

    if [[ "$rc" -eq 0 ]]; then
        success "$label ($((SECONDS - start))s)"
    else
        error "$label failed after $((SECONDS - start))s"
        cat "$log" >&2
    fi

    rm -f "$log"
    return "$rc"
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }
# Run a command with root rights. On the installer ISO we are already
# root and sudo may not even be installed; on an installed system use
# sudo as before.
as_root() {
    if [[ "$EUID" -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

get_var() {
    local key="$1"
    [[ -f "$VARS" ]] || return 1
    sed -nE "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"([^\"]*)\";.*/\1/p" "$VARS" | head -n1
}
# Rewrite one `key = "value";` in a variables file.
#
# sed rather than python3, because this also runs inside the installer ISO
# during a clean install and python3 is not something to depend on there.
set_var_in() {
    local file="$1" key="$2" value="$3"
    [[ -f "$file" ]] || die "Missing $file"

    grep -qE "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"" "$file" ||
        die "Could not find variable: $key"

    local esc
    esc="$(printf '%s' "$value" | sed -e 's/[\\&|]/\\&/g')"

    sed -i -E "s|^([[:space:]]*${key}[[:space:]]*=[[:space:]]*)\"[^\"]*\"(;.*)\$|\1\"${esc}\"\2|" "$file"
}

set_var() { set_var_in "$VARS" "$1" "$2"; }

# Toggle nvidia.enable in a variables file.
#
# The flag lives inside the nested `hardware.nvidia = { ... }` block, so a
# blind key match could hit an unrelated `enable` elsewhere in the file.
# The edit is therefore scoped: locate the block, then the first `enable =`
# line after it, and rewrite exactly that line.
set_nvidia_var() {
    local file="$1" value="$2" start target line
    [[ -f "$file" ]] || die "Missing $file"
    [[ "$value" == "true" || "$value" == "false" ]] || die "nvidia enable must be true or false"

    start="$(grep -nE '^[[:space:]]*nvidia[[:space:]]*=[[:space:]]*\{' "$file" | head -n1 | cut -d: -f1 || true)"
    [[ -n "$start" ]] || die "Could not find the nvidia = { block in $file"

    target="$(awk -v s="$start" 'NR > s && /^[[:space:]]*enable[[:space:]]*=[[:space:]]*(true|false);/ { print NR; exit }' "$file")"
    [[ -n "$target" ]] || die "Could not find nvidia.enable in $file"

    sed -i "${target}s|= .*;|= ${value};|" "$file"

    line="$(sed -n "${target}p" "$file")"
    [[ "$line" =~ enable[[:space:]]*=[[:space:]]*${value} ]] ||
        die "Failed to set nvidia.enable = $value in $file"
}

get_nvidia_var() {
    local file="$1" start target
    [[ -f "$file" ]] || return 1
    start="$(grep -nE '^[[:space:]]*nvidia[[:space:]]*=[[:space:]]*\{' "$file" | head -n1 | cut -d: -f1 || true)"
    [[ -n "$start" ]] || return 1
    target="$(awk -v s="$start" 'NR > s && /^[[:space:]]*enable[[:space:]]*=[[:space:]]*(true|false);/ { print NR; exit }' "$file")"
    [[ -n "$target" ]] || return 1
    sed -n "${target}p" "$file" | sed -nE 's/.*enable[[:space:]]*=[[:space:]]*(true|false);.*/\1/p'
}

backup_config() {
    local stamp backup
    stamp="$(date +%Y%m%d-%H%M%S)"
    backup="$ROOT/.setup-backups/$stamp"
    mkdir -p "$backup"
    [[ -f "$VARS" ]] && cp -a "$VARS" "$backup/"
    [[ -f "$ROOT/$HOST_DIR/hardware-configuration.nix" ]] &&
        cp -a "$ROOT/$HOST_DIR/hardware-configuration.nix" "$backup/"
    success "Backup created: $backup"
}

flake_check() {
    need_cmd nix
    section "Flake validation"
    run_cmd "nix flake check"
    if ! nix flake check; then
        error "Flake check failed."
        return 1
    fi
    success "Flake check passed."
}

dry_build() {
    need_cmd nix
    section "NixOS dry build"
    run_cmd "nixos-rebuild dry-build --flake .#$FLAKE_HOST"
    if ! sudo nixos-rebuild dry-build --flake "$FLAKE_TARGET"; then
        error "Dry-build failed."
        return 1
    fi
    success "Dry-build passed."
}

rebuild() {
    need_cmd nix
    if ! flake_check; then
        error "Rebuild stopped: flake does not evaluate."
        return 1
    fi
    section "NixOS rebuild"
    run_cmd "nixos-rebuild switch --flake .#$FLAKE_HOST"
    if ! sudo nixos-rebuild switch --flake "$FLAKE_TARGET"; then
        error "Rebuild failed. The running system was not changed."
        return 1
    fi
    success "System rebuilt and switched successfully."
}

update_config() {
    need_cmd nix
    section "Update configuration"
    cd "$ROOT"

    # git is optional: without a usable repository there is nothing to
    # pull, and the flake lock is updated in place either way. Only where
    # the new inputs come from differs, not what the update does.
    if command -v git >/dev/null 2>&1 && [[ -d "$ROOT/.git" ]] &&
        git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
        git config --global --add safe.directory "$ROOT" 2>/dev/null || true
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
            warning "Working tree contains uncommitted changes."
            git status --short || true
            if ! confirm "Continue with update?"; then
                success "Update cancelled."
                return 0
            fi
        fi
        run_cmd "git pull --ff-only"
        if ! git pull --ff-only; then
            error "git pull failed (local changes or no network)."
            return 1
        fi
    else
        warning "No usable git repository here; skipping the pull."
        info "Flake inputs still update below; the checkout itself stays as it is."
    fi

    run_cmd "nix flake update"
    if ! nix flake update; then
        error "nix flake update failed."
        return 1
    fi
    if ! flake_check; then
        error "Update left the flake broken; check the diff before rebuilding."
        return 1
    fi
    if confirm "Rebuild and switch now?"; then
        rebuild
    else
        success "Configuration updated. Rebuild when ready."
    fi
}

rollback() {
    section "Rollback"
    warning "This switches to the previous NixOS generation."
    if ! confirm "Continue with rollback?"; then
        success "Rollback cancelled."
        return 0
    fi
    if ! sudo nixos-rebuild switch --rollback; then
        error "Rollback failed."
        return 1
    fi
    success "Rollback completed."
}

list_generations() {
    section "NixOS generations"
    if ! sudo nix-env --list-generations --profile /nix/var/nix/profiles/system; then
        error "Could not list generations."
        return 1
    fi
}

# Write a hardware configuration.
#
# $1 is the root to describe: empty means the running system, otherwise a
# mounted target such as /mnt.
#
# That argument is the whole point. nixos-generate-config reports the
# filesystems of whichever root it is pointed at, so running it without
# --root from the installer ISO describes the ISO's own overlay and tmpfs
# mounts. There used to be no way to express the distinction, which is how a
# clean install could carry the previous machine's UUIDs into the new system.
write_hardware_config() {
    local target_root="$1" dest="$2" tmp

    mkdir -p "$(dirname "$dest")"

    # Generate into a temporary file first: a failure must not leave a
    # truncated hardware-configuration.nix behind in the tree.
    tmp="$(mktemp)" || return 1

    if [[ -n "$target_root" ]]; then
        if ! nixos-generate-config --root "$target_root" --show-hardware-config >"$tmp"; then
            rm -f "$tmp"
            return 1
        fi
    else
        # shellcheck disable=SC2024  # sudo is for probing hardware; the target is user-owned
        if ! sudo nixos-generate-config --show-hardware-config >"$tmp"; then
            rm -f "$tmp"
            return 1
        fi
    fi

    if [[ ! -s "$tmp" ]]; then
        error "nixos-generate-config produced an empty configuration."
        rm -f "$tmp"
        return 1
    fi

    mv "$tmp" "$dest"
}

refresh_hardware() {
    need_cmd nixos-generate-config
    section "Hardware configuration"

    # Regenerating from the installer would describe the installer.
    if ci_is_live_installer; then
        warning "This looks like the NixOS installer environment."
        warning "Generating here describes the ISO, not the system on disk."
        info "For a fresh machine use: ./setup.sh clean-install"
        if ! confirm "Generate anyway?"; then
            success "Hardware regeneration cancelled."
            return 0
        fi
    fi

    backup_config
    if ! write_hardware_config "" "$ROOT/$HOST_DIR/hardware-configuration.nix"; then
        error "Could not regenerate the hardware configuration."
        return 1
    fi
    success "Hardware configuration regenerated."
    warning "Review the generated file before rebuilding."
}

detect_nvidia() {
    command -v lspci >/dev/null 2>&1 && lspci -nn | grep -qi NVIDIA
}

install_flow() {
    # This flow ends in `nixos-rebuild switch`, which needs a running NixOS.
    # From the installer ISO it would do a lot of work and then fail at the last
    # step, so it redirects instead.
    if ci_is_live_installer; then
        section "Wrong flow for this environment"
        warning "This is the NixOS installer, and this option configures a system"
        warning "that is already running NixOS. It ends in nixos-rebuild switch,"
        warning "which cannot work from here."
        echo
        info "For a fresh machine you want the clean installer:"
        info "  ./setup.sh clean-install --dry-run    review the plan"
        info "  ./setup.sh clean-install              do it"
        echo
        # then-branch of `if` runs with errexit active, so the installer
        # keeps its safety guarantees (a bare `&& { ...; }` list would not).
        if confirm "Run the clean installer now?"; then
            ci_install_entry
        fi
        return 0
    fi

    # nix only: this pass never runs git (a checkout without .git must work).
    need_cmd nix

    section "NixOS installation / setup"

    # Defaults from lib/variables.nix -- the very file this pass rewrites --
    # with the live session used only when the file has no answer at all.
    local def_user def_name def_host def_git def_email def_tz def_locale
    def_user="$(get_var username || true)"
    def_name="$(get_var name || true)"
    def_host="$(get_var hostname || true)"
    def_git="$(get_var gitUser || true)"
    def_email="$(get_var email || true)"
    def_tz="$(get_var timezone || true)"
    def_locale="$(get_var locale || true)"

    local username="${def_user:-${SUDO_USER:-${USER:-}}}" full_name hostname git_user git_email timezone locale
    local nvidia="false" ans=""

    read -r -p "  Linux username [$username]: " username
    username="${username:-${def_user:-${SUDO_USER:-${USER:-}}}}"
    [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "Invalid Linux username."
    ci_username_ok "$username" || die "Invalid Linux username."

    read -r -p "  Full name${def_name:+ [$def_name]}: " full_name
    full_name="${full_name:-$def_name}"
    [[ -n "$full_name" ]] || die "Full name cannot be empty."

    # Same normaliser the clean installer uses: RFC 1123 shape, lowercase.
    def_host="${def_host:-$(hostname -s 2>/dev/null || echo nixos)}"
    def_host="$(ci_normalize_hostname "$def_host" 2>/dev/null || printf '%s' "$def_host")"
    read -r -p "  Hostname [$def_host]: " hostname
    hostname="${hostname:-$def_host}"
    hostname="$(ci_normalize_hostname "$hostname")" || die "Invalid hostname."

    read -r -p "  Git username${def_git:+ [$def_git]}: " git_user
    git_user="${git_user:-$def_git}"
    read -r -p "  Git email${def_email:+ [$def_email]}: " git_email
    git_email="${git_email:-$def_email}"
    # Empty is legal for git (it only warns when committing); anything
    # present has to actually look like an address.
    if [[ -n "$git_email" ]]; then
        ci_email_ok "$git_email" || die "Invalid git email."
    fi

    read -r -p "  Timezone [${def_tz:-Asia/Kolkata}]: " timezone
    timezone="${timezone:-${def_tz:-Asia/Kolkata}}"
    read -r -p "  Locale [${def_locale:-en_US.UTF-8}]: " locale
    locale="${locale:-${def_locale:-en_US.UTF-8}}"

    # A timezone zoneinfo does not have becomes a dangling /etc/localtime
    # at activation. Re-ask; forcing an unknown one through stays possible.
    local zdir
    if zdir="$(ci_zoneinfo_dir)"; then
        while ! [[ -e "$zdir/$timezone" ]]; do
            warning "Timezone '$timezone' not found in $zdir."
            read -r -p "  Use it anyway? [y/N]: " ans || die "Aborted."
            if [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]]; then break; fi
            read -r -p "  Timezone [${def_tz:-Asia/Kolkata}]: " timezone
            timezone="${timezone:-${def_tz:-Asia/Kolkata}}"
        done
    fi

    if detect_nvidia; then
        nvidia=true
        info "NVIDIA GPU detected."
    else
        read -r -p "  Enable NVIDIA support anyway? [y/N]: " ans
        ans="${ans:-n}"
        if [[ "$ans" =~ ^[Yy]$ ]]; then nvidia=true; fi
    fi

    echo
    section "Review"
    printf '  Username : %s\n' "$username"
    printf '  Full name: %s\n' "$full_name"
    printf '  Hostname : %s\n' "$hostname"
    printf '  Git user : %s\n' "$git_user"
    printf '  Git email: %s\n' "$git_email"
    printf '  Timezone : %s\n' "$timezone"
    printf '  Locale   : %s\n' "$locale"
    printf '  NVIDIA   : %s\n' "$nvidia"
    if ! confirm "Apply these settings?"; then
        warning "Installation cancelled."
        return 0
    fi

    backup_config
    set_var username "$username"
    set_var name "$full_name"
    set_var hostname "$hostname"
    set_var gitUser "$git_user"
    set_var email "$git_email"
    set_var timezone "$timezone"
    set_var locale "$locale"

    if [[ -n "$(get_nvidia_var "$VARS" || true)" ]]; then
        set_nvidia_var "$VARS" "$nvidia"
    else
        warning "No nvidia.enable found in lib/variables.nix; skipped."
    fi

    # Every step below is guarded: this function is sometimes called from a
    # tested context, where errexit would be suspended, so it must not rely
    # on it.
    if ! refresh_hardware; then
        error "Hardware refresh failed; stopping before any rebuild."
        return 1
    fi
    if ! flake_check; then
        error "Flake check failed; stopping before any rebuild."
        return 1
    fi
    if ! dry_build; then
        error "Dry build failed; stopping before any rebuild."
        return 1
    fi

    if confirm "Switch to this configuration now?"; then
        if ! rebuild; then
            error "Rebuild failed; the running system is unchanged."
            return 1
        fi
        if id "$username" >/dev/null 2>&1; then
            info "Set the Linux password for $username. It is never stored in Nix."
            as_root passwd "$username"
        else
            warning "User '$username' is not currently present. Set its password after activation:"
            printf '  sudo passwd %q\n' "$username"
        fi
        success "Installation completed."
    else
        success "Setup prepared but not switched."
    fi
}

test_install() {
    section "Installer preview"

    # Defaults come from lib/variables.nix -- the same file a real run
    # starts from -- so the preview shows what would actually be written
    # rather than placeholders that no install ever used. Falling back to
    # the old literals only when the file itself has no answer.
    local def_user def_name def_host def_gituser def_email def_tz def_locale
    def_user="$(get_var username || true)"
    def_name="$(get_var name || true)"
    def_host="$(get_var hostname || true)"
    def_gituser="$(get_var gitUser || true)"
    def_email="$(get_var email || true)"
    def_tz="$(get_var timezone || true)"
    def_locale="$(get_var locale || true)"

    local username="${SUDO_USER:-${USER:-${def_user:-testuser}}}" full_name hostname git_user git_email timezone locale
    # Was "${username:-$SUDO_USER}", which aborts under set -u whenever the
    # script is not run through sudo.
    read -r -p "  Test username [$username]: " username
    username="${username:-${SUDO_USER:-${USER:-${def_user:-testuser}}}}"
    read -r -p "  Test full name [${def_name:-Test User}]: " full_name
    full_name="${full_name:-${def_name:-Test User}}"
    read -r -p "  Test hostname [${def_host:-nixos-test}]: " hostname
    hostname="${hostname:-${def_host:-nixos-test}}"
    read -r -p "  Test Git username [${def_gituser:-testuser}]: " git_user
    git_user="${git_user:-${def_gituser:-testuser}}"
    read -r -p "  Test Git email [${def_email:-test@example.com}]: " git_email
    git_email="${git_email:-${def_email:-test@example.com}}"
    read -r -p "  Test timezone [${def_tz:-Asia/Kolkata}]: " timezone
    timezone="${timezone:-${def_tz:-Asia/Kolkata}}"
    read -r -p "  Test locale [${def_locale:-en_US.UTF-8}]: " locale
    locale="${locale:-${def_locale:-en_US.UTF-8}}"
    echo
    info "No files will be changed."
    printf '  username = "%s";\n' "$username"
    printf '  name = "%s";\n' "$full_name"
    printf '  hostname = "%s";\n' "$hostname"
    printf '  gitUser = "%s";\n' "$git_user"
    printf '  email = "%s";\n' "$git_email"
    printf '  timezone = "%s";\n' "$timezone"
    printf '  locale = "%s";\n' "$locale"
    echo
    success "Installer preview complete. Nothing was modified."
}

system_overview() {
    section "System overview"
    printf '  Host:    %s\n' "$(hostname)"
    printf '  Kernel:  %s\n' "$(uname -r)"
    printf '  Nix:     %s\n' "$(nix --version 2>/dev/null || echo unavailable)"
    printf '  Uptime:  %s\n' "$(uptime_human)"
}

# Uptime, without `uptime -p`
#
# -p is a procps extension and the uptime on this system rejects it, so
# all three call sites used to fall back to their placeholder string.
# /proc/uptime is always there and needs no external command.

uptime_human() {
    local secs d h m

    if [[ ! -r /proc/uptime ]]; then
        printf 'unknown'
        return
    fi

    read -r secs _ </proc/uptime
    secs="${secs%%.*}"

    d=$((secs / 86400))
    h=$((secs % 86400 / 3600))
    m=$((secs % 3600 / 60))

    if [[ "$d" -gt 0 ]]; then
        printf '%dd %dh' "$d" "$h"
    elif [[ "$h" -gt 0 ]]; then
        printf '%dh %dm' "$h" "$m"
    else
        printf '%dm' "$m"
    fi
}

# One compact "user · kernel · nix · uptime" line for the menu panel.
overview_facts() {
    local nixv
    nixv="$(nix --version 2>/dev/null | grep -o '[0-9.]\+' | head -1)"

    printf '%s · %s · nix %s · up %s' \
        "${USER:-$(whoami 2>/dev/null || echo user)}" \
        "$(uname -r)" \
        "${nixv:-?}" \
        "$(uptime_human)"
}

# One menu row: number, label, dimmed description. The number keeps its
# colour so the eye can jump to it; the label is padded to a fixed
# column so the descriptions line up.
menu_item() {
    local num="$1" label="$2" desc="$3"

    printf '   %b%2s%b  %-22s%b%s%b\n' \
        "$CYAN" "$num" "$RESET" "$label" "$DIM" "$desc" "$RESET"
}

# The menu has two faces. On the installer ISO the useful actions are
# installing and checking; on an installed system the installation entries
# are hidden entirely -- offering "Fresh install" on a machine that already
# runs Sunflower is how a disk gets erased by muscle memory.
#
# Maintenance calls are guarded (`|| true`): those functions are written
# with explicit error handling and must not take the script down with them.
# The installer is deliberately NOT guarded: ci_install_entry owns the ERR
# trap and returns 0 only for user aborts, so a real failure stops the
# script instead of falling back into the menu.
menu() {
    local live=0 choice
    if ci_is_live_installer; then live=1; fi

    while true; do
        clear_screen
        echo

        if [[ "$live" -eq 1 ]]; then
            panel "Sunflower Installer" "v$VERSION" "$(overview_facts)"
        else
            panel "Sunflower Configuration Manager" "v$VERSION" "$(overview_facts)"
        fi
        echo

        if [[ "$live" -eq 1 ]]; then
            printf '  %b%bInstaller environment detected. Choose 1 to install NixOS.%b\n\n' \
                "$YELLOW" "$BOLD" "$RESET"

            printf '  %b%bINSTALL%b\n' "$CYAN" "$BOLD" "$RESET"
            menu_item 1 "Fresh install" "questionnaire, erases the target disk"
            menu_item 2 "Install dry-run" "answer the questions, change nothing"

            echo
            printf '  %b%bCHECKS%b\n' "$CYAN" "$BOLD" "$RESET"
            menu_item 3 "Verify boot" "re-check an install mounted at /mnt"
            menu_item 4 "Identity preview" "preview the prompts only"
            menu_item 5 "Check flake" "evaluate the flake"

            echo
            menu_item 0 "Exit" ""
            echo

            if ! read -r -p "  Select: " choice; then
                printf '\n'
                exit 0
            fi

            case "$choice" in
            1)
                ci_install_entry
                pause
                ;;
            2)
                ci_install_entry --dry-run
                pause
                ;;
            3)
                verify_boot || true
                pause
                ;;
            4)
                test_install || true
                pause
                ;;
            5)
                flake_check || true
                pause
                ;;
            0)
                clear_screen
                exit 0
                ;;
            *)
                warning "Invalid option."
                sleep 1
                ;;
            esac
            continue
        fi

        printf '  %b%bMAIN%b\n' "$CYAN" "$BOLD" "$RESET"
        menu_item 1 "Upgrade" "git pull, flake update, rebuild"
        menu_item 2 "Free disk space" "old generations, GC, optimise"
        menu_item 3 "Rebuild / Switch" "validate then switch"
        menu_item 4 "Dry rebuild" "build without switching"
        menu_item 5 "Check flake" "evaluate the flake"

        echo
        printf '  %b%bSYSTEM%b\n' "$CYAN" "$BOLD" "$RESET"
        menu_item 6 "Rollback" "previous generation"
        menu_item 7 "List generations" "system profile history"
        menu_item 8 "Refresh hardware" "regenerate hardware config"
        menu_item 9 "Configure identity" "on an already-installed system"

        echo
        printf '  %b%bMAINTENANCE%b\n' "$CYAN" "$BOLD" "$RESET"
        menu_item 10 "Maintenance dashboard" "guarded full cleanup"
        menu_item 11 "Garbage collection" "reclaim store space"
        menu_item 12 "Optimize store" "deduplicate the store"
        menu_item 13 "Verify store" "check store integrity"
        menu_item 14 "Systemd health" "failed units"
        menu_item 15 "Store usage" "disk footprint"

        echo
        menu_item 0 "Exit" ""
        echo

        if ! read -r -p "  Select: " choice; then
            printf '\n'
            exit 0
        fi

        case "$choice" in
        1)
            update_config || true
            pause
            ;;
        2)
            free_space || true
            pause
            ;;
        3)
            rebuild || true
            pause
            ;;
        4)
            dry_build || true
            pause
            ;;
        5)
            flake_check || true
            pause
            ;;
        6)
            rollback || true
            pause
            ;;
        7)
            list_generations || true
            pause
            ;;
        8)
            refresh_hardware || true
            pause
            ;;
        9)
            install_flow || true
            pause
            ;;
        10) m_maintenance_dashboard || true ;;
        11)
            m_garbage_collect || true
            pause
            ;;
        12)
            m_optimize_store || true
            pause
            ;;
        13)
            m_verify_store || true
            pause
            ;;
        14)
            m_systemd_health || true
            pause
            ;;
        15)
            m_store_usage || true
            pause
            ;;
        0)
            clear_screen
            exit 0
            ;;
        *)
            warning "Invalid option."
            sleep 1
            ;;
        esac
    done
}

# Integrated maintenance dashboard (from cleanup.sh)
M_NIXOS_DIR="$ROOT"
M_FLAKE_TARGET="$ROOT#$FLAKE_HOST"
M_KEEP_GENERATIONS=5
M_ICON_OK="✓"
M_ICON_INFO="ℹ"
M_ICON_CLEAN="✦"
M_ICON_NIX=""
M_ICON_GIT=""
M_ICON_SYSTEM="⚙"
M_ICON_DISK="▣"
M_ICON_TRASH="✕"
M_ICON_CHECK="✓"

# The maintenance dashboard used to carry its own copy of the log and
# framing helpers (m_section, m_info, m_run, m_header, ...). They are
# gone; it now speaks the shared vocabulary defined at the top of the
# file. The M_ICON_* and M_* configuration values above stay, because
# the printf call sites in this section reference the icons directly.

# Safety

m_check_environment() {

    section "Environment"

    if [[ $EUID -eq 0 ]]; then
        error "Do not run this script with sudo."
        echo
        echo "  Run it as your normal user:"
        echo
        echo "    ./setup.sh maintain"
        echo
        exit 1
    fi

    if [[ ! -d "$M_NIXOS_DIR" ]]; then
        error "NixOS directory not found:"
        echo "    $M_NIXOS_DIR"
        exit 1
    fi

    if ! command -v nix >/dev/null 2>&1; then
        error "Nix command not found."
        exit 1
    fi

    if ! command -v nixos-rebuild >/dev/null 2>&1; then
        error "nixos-rebuild not found."
        exit 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        # Warning, not an error: the whole point of this pass is that a
        # checkout without git (a downloaded archive, a copied tree) can be
        # maintained. Only the git-status panel needs it, and that panel
        # says so itself.
        warning "git not found; skipping the git status panel."
    fi

    success "NixOS environment detected."
    info "Configuration: $M_NIXOS_DIR"
    info "Flake target:  $M_FLAKE_TARGET"
}

# Git

m_check_git() {

    section "${M_ICON_GIT} Git status"

    cd "$M_NIXOS_DIR"

    # Without git, or in a tree that never had a .git, there is no status
    # to report -- and neither condition says anything about the system.
    if ! command -v git >/dev/null 2>&1; then
        warning "git is absent; skipping the status panel."
        return 0
    fi
    git config --global --add safe.directory "$M_NIXOS_DIR" 2>/dev/null || true
    if ! git -C "$M_NIXOS_DIR" rev-parse --git-dir >/dev/null 2>&1; then
        info "Not a git repository; there is no status to show."
        return 0
    fi

    if [[ -n "$(git status --porcelain)" ]]; then

        warning "Working tree contains uncommitted changes."

        echo
        git status --short

        echo
        printf '%b\n' "${YELLOW}  This is allowed, but review your changes before continuing.${RESET}"

    else

        success "Working tree is clean."

    fi
}

# Flake check

m_check_flake() {

    section "${M_ICON_NIX} Flake validation"

    run_cmd "nix flake check"

    if nix flake check; then
        success "Flake check passed."
    else
        error "Flake check failed."
        return 1
    fi
}

# Dry build

m_dry_build() {

    section "${M_ICON_CHECK} NixOS configuration"

    run_cmd "nixos-rebuild dry-build"

    if sudo nixos-rebuild dry-build --flake "$M_FLAKE_TARGET"; then
        success "Dry-build passed."
        return 0
    fi

    error "Dry-build failed."
    return 1
}

# Generation information

m_get_generations() {

    sudo nix-env \
        --list-generations \
        --profile /nix/var/nix/profiles/system
}

m_get_current_generation() {

    m_get_generations |
        awk '/\(current\)/ {print $1}'
}

# Generation dashboard

m_generation_status() {

    section "${M_ICON_SYSTEM} System generations"

    local output
    local current
    local total

    output="$(m_get_generations)"
    current="$(echo "$output" | awk '/\(current\)/ {print $1}')"
    total="$(echo "$output" | awk 'NF {count++} END {print count+0}')"

    echo
    printf '  %b Current generation: %b%s%b\n' \
        "${GREEN}${M_ICON_OK}${RESET}" \
        "${BOLD}" \
        "$current" \
        "${RESET}"

    printf '  %b Total generations:  %b%s%b\n' \
        "${BLUE}${M_ICON_INFO}${RESET}" \
        "${BOLD}" \
        "$total" \
        "${RESET}"

    printf '  %b Keeping:            %b%s%b\n' \
        "${CYAN}${M_ICON_CLEAN}${RESET}" \
        "${BOLD}" \
        "$M_KEEP_GENERATIONS" \
        "${RESET}"

    echo
}

# Generation cleanup

m_cleanup_generations() {

    section "${M_ICON_CLEAN} Generation cleanup"

    local output
    local current
    local generations
    local total
    local delete_count
    local old_generations

    output="$(m_get_generations)"

    current="$(echo "$output" | awk '/\(current\)/ {print $1}')"

    mapfile -t generations < <(
        echo "$output" |
            awk '{print $1}'
    )

    total="${#generations[@]}"

    if ((total <= M_KEEP_GENERATIONS)); then
        success "Nothing to remove."
        info "Only $total generation(s) exist."
        return
    fi

    delete_count=$((total - M_KEEP_GENERATIONS))

    old_generations=(
        "${generations[@]:0:$delete_count}"
    )

    echo
    warning "Old generations selected for removal:"
    echo

    for generation in "${old_generations[@]}"; do
        printf '    %b generation %s%b\n' \
            "${RED}${M_ICON_TRASH}${RESET}" \
            "$generation" \
            "${RESET}"
    done

    echo
    info "Current generation $current is protected."
    info "Newest $M_KEEP_GENERATIONS generations will remain."

    if confirm "Remove these generations?"; then

        run_cmd "Removing old generations..."

        sudo nix-env \
            --profile /nix/var/nix/profiles/system \
            --delete-generations \
            "${old_generations[@]}"

        success "Old generations removed."

    else

        warning "Generation cleanup cancelled."

    fi
}

# Garbage collection

m_garbage_collect() {

    section "${M_ICON_TRASH} Garbage collection"

    info "Scanning for unreachable store paths..."

    local dead_paths
    dead_paths="$(
        nix-store --gc --print-dead 2>/dev/null || true
    )"

    if [[ -z "$dead_paths" ]]; then

        success "No unreachable store paths found."
        return

    fi

    local count
    count="$(echo "$dead_paths" | wc -l)"

    info "Approximately $count unreachable paths found."

    if confirm "Run garbage collection?"; then

        run_cmd "Running Nix garbage collection..."

        sudo nix-collect-garbage

        success "Garbage collection completed."

    else

        warning "Garbage collection cancelled."

    fi
}

# Store optimization

m_optimize_store() {

    section "${M_ICON_NIX} Store optimization"

    if confirm "Optimize the Nix store?"; then

        run_cmd "Optimizing Nix store..."

        sudo nix-store --optimise

        success "Nix store optimization completed."

    else

        warning "Store optimization skipped."

    fi
}

# Store verification

m_verify_store() {

    section "${M_ICON_CHECK} Store verification"

    warning "This can take a while."

    if ! confirm "Verify Nix store contents?"; then
        warning "Store verification skipped."
        return
    fi

    # The one operation in this script that a spinner genuinely improves:
    # it runs for minutes, prints nothing at all while it succeeds, and
    # prints the corrupt paths when it does not -- which spinner replays to
    # stderr. The other long operations here (nix-collect-garbage,
    # --optimise, flake check, dry-build) each end on a summary line worth
    # reading, so they stay streaming.
    if spinner "Verifying Nix store" sudo nix-store --verify --check-contents; then
        success "Nix store verification passed."
    else
        error "Nix store verification reported problems."
    fi
}

# Systemd

m_systemd_health() {

    section "${M_ICON_SYSTEM} Systemd health"

    local failed

    failed="$(
        systemctl \
            --failed \
            --no-legend \
            --no-pager ||
            true
    )"

    if [[ -z "$failed" ]]; then

        success "No failed systemd units."

    else

        warning "Failed systemd units detected:"
        echo
        systemctl --failed --no-pager

    fi
}

# Disk usage

m_store_usage() {

    section "${M_ICON_DISK} Nix store"

    local usage

    usage="$(du -sh /nix/store 2>/dev/null | awk '{print $1}')"

    echo
    printf '  %b Nix store size: %b%s%b\n' \
        "${CYAN}${M_ICON_DISK}${RESET}" \
        "${BOLD}" \
        "$usage" \
        "${RESET}"

    echo

    df -h /nix
}

# System overview

m_system_overview() {

    section "${M_ICON_SYSTEM} System overview"

    local hostname
    local kernel
    local nix_version
    local uptime

    hostname="$(hostname)"
    kernel="$(uname -r)"
    nix_version="$(nix --version)"
    uptime="$(uptime_human)"

    printf '  %b Host:       %s\n' "${CYAN}${M_ICON_SYSTEM}${RESET}" "$hostname"
    printf '  %b Kernel:     %s\n' "${BLUE}${M_ICON_INFO}${RESET}" "$kernel"
    printf '  %b Nix:        %s\n' "${MAGENTA}${M_ICON_NIX}${RESET}" "$nix_version"
    printf '  %b Uptime:     %s\n' "${GREEN}${M_ICON_OK}${RESET}" "$uptime"
}

# Full maintenance is implemented by m_maintenance_dashboard above.
m_maintenance_dashboard() {
    clear_screen
    panel "NixOS Maintenance" "v$VERSION" "System maintenance dashboard"
    echo
    m_check_environment
    m_check_git
    echo
    if ! m_check_flake; then
        error "Maintenance stopped."
        pause
        return
    fi
    if ! m_dry_build; then
        error "Maintenance stopped."
        echo
        echo "Fix the NixOS configuration before cleanup."
        pause
        return
    fi
    m_generation_status
    m_cleanup_generations
    m_garbage_collect
    m_optimize_store
    m_verify_store
    m_systemd_health
    m_store_usage
    echo
    section "Final configuration check"
    run_cmd "Running final dry-build..."
    if sudo nixos-rebuild dry-build --flake "$M_FLAKE_TARGET"; then
        success "Final dry-build passed."
    else
        error "Final dry-build failed."
    fi
    echo
    hr
    echo
    printf '%b\n' "${GREEN}${BOLD}  ${M_ICON_OK} Maintenance complete${RESET}"
    echo
    printf '  %b Current generation: %s\n' "${GREEN}${M_ICON_SYSTEM}${RESET}" "$(m_get_current_generation)"
    printf '  %b Generations kept:  %s\n' "${CYAN}${M_ICON_CLEAN}${RESET}" "$M_KEEP_GENERATIONS"
    echo
    printf '%b\n' "${DIM}  Your NixOS configuration was not modified.${RESET}"
    echo
    pause
}

# ============================================================
# CLEAN INSTALLATION
#
# A different workflow from install_flow. That one configures a system that
# is ALREADY installed and ends in nixos-rebuild switch. This one runs from
# the official installer ISO, owns the disk, and ends in nixos-install.
# Both are kept, because they are not the same job.
#
# Two environments exist during a clean install and must never be confused:
#
#   /       the live installer
#   /mnt    the system being installed
#
# Anything describing filesystems is evaluated against /mnt, and anything
# concerning boot is verified against /mnt too.
#
# THE STATE MACHINE
#
#   entry (trap armed)
#     -> preflight/identity/disks/review      [cancellable: return 0]
#     -> typed confirmations                  [cancellable: return 0]
#     -> release, partition, format, mount     [DESTRUCTIVE from here on]
#     -> swap, repo copy, identity, hardware
#     -> flake check, build, nixos-install
#     -> ownership, passwords, verification
#     -> cleanup, success, optional reboot
#
# Failure contract:
#
#   * Before the confirmations every failure path returns 0 after printing
#     a warning; the menu survives a cancelled install.
#   * After the confirmations nothing may `return 1` into a tested context:
#     a tested context (cmd || true, if ! cmd) suspends errexit INSIDE the
#     called function, which would let a failed wipefs continue the script.
#     Every pipeline function is therefore called BARE, so errexit and the
#     ERR trap are active inside it. Explicit error handling inside those
#     functions returns 1, the bare call fails, and ci_on_error prints the
#     panel (phase, command, line, mount state) and exits 1.
#   * The EXIT trap always tears down install-time swap and scratch space
#     and restores the cursor; the target stays mounted for inspection.
#
# Boot persistence is treated as part of installation, not as cleanup. This
# repository sets efiInstallAsRemovable = true together with
# efi.canTouchEfiVariables = false, so on UEFI GRUB is written only to
# \EFI\BOOT\BOOTX64.EFI and registers no NVRAM entry of its own. A leftover
# entry from a previous install therefore outranks it and the firmware boots
# the old system. This installer refuses to report success while such an
# entry is still present.
#
# On legacy BIOS the same repository defaults are invalid (nixpkgs asserts
# efiInstallAsRemovable implies efiSupport, and GRUB needs a real device to
# write an MBR into), so hardware-configuration.nix receives a mkForce
# override for the three grub keys after generation.
# ============================================================

CI_TARGET="/mnt"
CI_ESP_LABEL="EFI"
CI_ROOT_LABEL="nixos"
CI_DRY_RUN=0

# Space arithmetic, derived from what this configuration actually ships
# (~7.5 GB of packages) rather than guessed per machine:
#
#   CI_BUILD_RESERVE_GB  kept free for the store and nix's temporaries;
#                        install-time swap is never allowed to eat into it.
#   CI_MIN_DISK_BYTES    below this the install is refused BEFORE anything
#                        is erased, instead of failing mid-build afterwards.
#   CI_WARN_DISK_BYTES   still possible, but worth saying out loud.
CI_BUILD_RESERVE_GB=10
CI_MIN_DISK_BYTES=12884901888  # 12 GiB
CI_WARN_DISK_BYTES=21474836480 # 20 GiB

# Decided by the pre-destructive flake validation: whether the copy placed
# on the target keeps its .git directory or is evaluated as a plain path.
# Empty means "not decided yet".
CI_STRIP_GIT=""

# GPT partition type GUIDs, as reported by lsblk PARTTYPE. sgdisk's
# two-letter codes are different (ef00/ef02/8300); both spellings appear
# below at their respective call sites.
CI_PTYPE_EFI="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
CI_PTYPE_BIOS="21686148-6449-6e6f-744e-656564454649"
CI_PTYPE_LINUX="0fc63daf-8483-4772-8e79-3d69d8477de4"

CI_DISK=""
CI_FIRMWARE="" # UEFI | BIOS (set by ci_firmware_detect)
CI_ESP=""      # ESP node; only meaningful in UEFI mode
CI_BIOS_PART=""
CI_ROOT_PART=""
CI_USER=""
CI_DEST=""
CI_EXPECT_HOSTNAME=""
CI_USER_UID=""
CI_USER_GID=""
CI_SYSTEM_PATH=""
CI_SWAPFILE=""

# GPU bus ids collected during the questionnaire, used when the machine
# actually has an NVIDIA card (PCI:<bus>@<domain>:<dev>:<func>).
CI_GPU_INTEL=""
CI_GPU_NVIDIA=""

# Password step records its outcome here; ci_final_verify reads it, because
# V_FAILED is reset by every verifier entry point.
CI_PW_ATTEMPTED=0
CI_PW_USER_OK=0

# Where we are in the state machine; ci_on_error prints this.
CI_PHASE="init"
CI_STARTED_DESTRUCTIVE=0
CI_IN_ERR=0

# Resolved by ci_preflight: the ISO does not guarantee one particular
# partitioner or one particular name for the FAT tool.
CI_PARTITIONER=""
CI_MKFS_FAT=""

# The ISO does not necessarily enable flakes, and nixos-install shells out
# to nix itself, so NIX_CONFIG is exported for the whole run; these flags
# belt-and-braces our own invocations.
CI_NIX_FLAGS=(--extra-experimental-features "nix-command flakes")

# A dry run must be reviewable on any machine, including one with no
# partitioning or installation tools at all, so a missing tool is reported
# rather than fatal.
ci_need_cmd() {
    if [[ "$CI_DRY_RUN" -eq 1 ]]; then
        command -v "$1" >/dev/null 2>&1 ||
            warning "absent here, required for a real run: $1"
        return 0
    fi
    need_cmd "$1"
}

ci_run() {
    if [[ "$CI_DRY_RUN" -eq 1 ]]; then
        printf '  %b%s%b %b[dry-run]%b %s\n' \
            "$MAGENTA" "$ICON_ARROW" "$RESET" "$DIM" "$RESET" "$*"
        return 0
    fi
    run_cmd "$*"
    "$@"
}

# Can we reach the binary cache?
#
# Checked explicitly because the alternative is discovering it as a wall of
# nix download errors after the disk has already been repartitioned.
ci_check_network() {
    local ok=0

    if command -v curl >/dev/null 2>&1; then
        curl -fsS --max-time 12 -o /dev/null https://cache.nixos.org/nix-cache-info 2>/dev/null && ok=1
    elif command -v ping >/dev/null 2>&1; then
        ping -c1 -W3 cache.nixos.org >/dev/null 2>&1 && ok=1
    else
        v_info "neither curl nor ping available; connectivity not tested"
        return 0
    fi

    if [[ "$ok" -eq 1 ]]; then
        v_ok "cache.nixos.org reachable"
        return 0
    fi

    v_fail "cannot reach cache.nixos.org"
    warning "This install downloads almost everything; it cannot run offline."
    info "Wired is usually automatic. If not:  sudo dhcpcd"
    info "Wi-Fi, easiest:  nmcli device wifi connect <SSID> password <password>"
    info "Wi-Fi, fallback: sudo systemctl start wpa_supplicant"
    info "                 then wpa_cli -i <iface>"
    return 1
}

# Everything this needs, checked in one pass before anything is touched.
#
# Discovering a missing mkfs after the partition table has already been
# written is the worst possible moment to find out, so the whole toolchain is
# resolved up front. Where a tool has more than one common name, or where two
# different tools would do, the alternative is accepted rather than demanded,
# so a stock installer ISO needs nothing installed.
ci_preflight() {
    section "Preflight"

    local -a missing=()
    local c

    for c in lsblk findmnt blkid wipefs mount umount mountpoint awk sed grep \
        chown stat mktemp swapon swapoff head tail sort tr; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done

    # nixos-install --flake shells out to jq when it resolves the flake, and
    # the parse check needs nix-instantiate; both ship with nix.
    for c in nix nix-instantiate nixos-generate-config nixos-install nixos-enter jq; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done

    # Either partitioner is fine.
    if command -v sgdisk >/dev/null 2>&1; then
        CI_PARTITIONER="sgdisk"
    elif command -v parted >/dev/null 2>&1; then
        CI_PARTITIONER="parted"
    else
        missing+=("sgdisk or parted")
    fi

    # dosfstools has used both names.
    if command -v mkfs.fat >/dev/null 2>&1; then
        CI_MKFS_FAT="mkfs.fat"
    elif command -v mkfs.vfat >/dev/null 2>&1; then
        CI_MKFS_FAT="mkfs.vfat"
    else
        missing+=("mkfs.fat or mkfs.vfat")
    fi

    command -v mkfs.ext4 >/dev/null 2>&1 || missing+=("mkfs.ext4")

    if [[ "${#missing[@]}" -gt 0 ]]; then
        for c in "${missing[@]}"; do error "missing: $c"; done
        echo
        error "A stock NixOS installer ISO provides all of these."
        info "If one really is absent, borrow it without installing anything:"
        info "  nix-shell -p gptfdisk parted dosfstools e2fsprogs efibootmgr util-linux"
        info "(gptfdisk provides sgdisk; either sgdisk or parted is enough.)"

        if [[ "$CI_DRY_RUN" -eq 1 ]]; then
            CI_PARTITIONER="${CI_PARTITIONER:-sgdisk}"
            CI_MKFS_FAT="${CI_MKFS_FAT:-mkfs.fat}"
            warning "Dry run continues so the plan can still be reviewed."
            return 0
        fi
        return 1
    fi

    v_ok "partitioner: $CI_PARTITIONER"
    v_ok "fat filesystem tool: $CI_MKFS_FAT"

    # Without efibootmgr a UEFI install cannot clean up the boot entries it
    # finds, and ci_handle_stale_efi will mark the finished install failed
    # at the very last step. Refusing here -- before anything is erased --
    # is the same verdict, delivered while it is still free to fix.
    if command -v efibootmgr >/dev/null 2>&1; then
        v_ok "efibootmgr present"
    elif [[ "$CI_FIRMWARE" == "UEFI" && "$CI_DRY_RUN" -eq 0 ]]; then
        error "efibootmgr is required for a UEFI install (stale boot entries are a verification failure)."
        info "A stock NixOS installer ISO provides it; otherwise:"
        info "  nix-shell -p efibootmgr"
        return 1
    else
        v_info "efibootmgr absent; stale UEFI entries could not be cleaned"
    fi

    if command -v git >/dev/null 2>&1; then
        v_ok "git present"
    else
        v_info "git absent; the copied repository will fall back to a plain path"
    fi

    # Only matters when the installer media is a loop-mounted image, but
    # that is exactly how findiso= boots, and the protection list needs to
    # trace the loop back to its backing disk.
    if command -v losetup >/dev/null 2>&1; then
        v_ok "losetup present"
    else
        v_info "losetup absent; a loop-mounted installer image cannot be traced to its disk"
    fi

    # The copy comes from here and the release step unmounts $CI_TARGET --
    # running the installer from a directory on the target would unmount
    # its own source half-way through.
    case "$ROOT" in
    "$CI_TARGET" | "$CI_TARGET"/*)
        if [[ "$CI_DRY_RUN" -eq 1 ]]; then
            warning "This script runs from under $CI_TARGET ($ROOT); a real run would release it from under itself."
        else
            error "This script is running from under $CI_TARGET ($ROOT)."
            error "Releasing the target would unmount it from under the installer. Move it first."
            return 1
        fi
        ;;
    esac

    # Reported rather than gated. The writable half of the ISO's /nix/store
    # is a tmpfs in RAM, so this number is what the build has to fit in until
    # swap is added on the target after mounting.
    local ram_kb
    ram_kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || printf 0)"
    if [[ "$ram_kb" -gt 0 ]]; then
        v_info "RAM $((ram_kb / 1024 / 1024)) GiB; the ISO store is RAM-backed until swap is added"
        if [[ "$ram_kb" -lt $((4 * 1024 * 1024)) && "$CI_DRY_RUN" -eq 0 ]]; then
            warning "RAM is under 4 GiB; the build will lean hard on install-time swap."
        fi
    fi

    if ! ci_check_network; then
        if [[ "$CI_DRY_RUN" -eq 1 ]]; then
            warning "Dry run continues anyway."
            return 0
        fi
        return 1
    fi

    success "Toolchain complete; nothing needs installing."
}

# Is this the NixOS installation ISO?
#
# This used to accept any overlay, tmpfs or squashfs root, which was wrong: a
# container has an overlay root too, so `install` inside one would have decided
# it was in an installer and offered to partition a disk. Testing caught it.
#
# Now it looks only for markers the ISO actually brings with it.
# VARIANT_ID=installer is set by the installation-CD module itself and is the
# most direct evidence; /iso and the read-only store are its own mounts.
ci_is_live_installer() {
    grep -qsE '^VARIANT_ID="?installer"?' /etc/os-release && return 0
    [[ -d /iso ]] && return 0
    findmnt -no TARGET /nix/.ro-store >/dev/null 2>&1 && return 0
    return 1
}

ci_require_live() {
    if ci_is_live_installer; then return 0; fi

    error "This is not the NixOS installer environment."
    error "No VARIANT_ID=installer, no /iso, no read-only store mount."
    error "Refusing to partition a disk from anything but the installer ISO."
    info "Preview the plan anywhere with:  ./setup.sh clean-install --dry-run"
    return 1
}

# The graphical ISO logs in as an unprivileged user, so this is a normal
# thing to hit rather than a mistake. When a passwordless sudo exists, take
# it and carry the command line over: SETUP_ARGS was captured at the top of
# the script exactly for this, and the guard variable stops a sudo that
# hands back the same uid from looping forever. The menu case (no
# arguments at all) re-enters this flow by name -- this function has
# exactly one caller, clean_install, and only on a real run.
ci_require_root() {
    if [[ "$EUID" -eq 0 ]]; then return 0; fi

    if command -v sudo >/dev/null 2>&1 &&
        [[ -z "${SUNFLOWER_SUDO_REEXEC:-}" ]] &&
        sudo -n true 2>/dev/null; then
        info "Re-running as root through passwordless sudo."
        SUNFLOWER_SUDO_REEXEC=1
        export SUNFLOWER_SUDO_REEXEC
        if [[ ${#SETUP_ARGS[@]} -gt 0 ]]; then
            exec sudo -E -- "$0" "${SETUP_ARGS[@]}"
        else
            exec sudo -E -- "$0" clean-install
        fi
    fi

    error "A clean installation has to run as root."
    info "Re-run it as:  sudo $0 ${SETUP_ARGS[*]:-clean-install}"
    info "(with a passwordless sudo the script re-runs itself as root automatically.)"
    return 1
}

# Every question in this flow is answered on a terminal.
ci_require_tty() {
    if [[ -t 0 && -t 1 ]]; then return 0; fi
    error "The installer is interactive; run it from a terminal (or use --dry-run)."
    return 1
}

# UEFI boots leave /sys/firmware/efi behind; legacy BIOS boots do not. This
# decides the partition layout, the mount plan, the bootloader verification
# and the stale-NVRAM step, so it is detected once, up front, everywhere.
ci_firmware_detect() {
    if [[ -d /sys/firmware/efi ]]; then
        CI_FIRMWARE="UEFI"
    else
        CI_FIRMWARE="BIOS"
    fi
}

# Every mount on the system as source<TAB>target pairs. Parsing with
# findmnt -P (shell-style variable quoting, escaped) instead of the raw
# output is what makes a target path containing a space survive: with
# IFS=tab the two fields separate exactly as printed. Plain
# `findmnt -rn -o SOURCE,TARGET` splits a space-containing mountpoint
# across fields and is unusable for this.
ci_all_mounts() {
    local line src mnt
    command -v findmnt >/dev/null 2>&1 || return 0
    while IFS= read -r line; do
        # SOURCE="..." TARGET="..."  (backslash-escaped inside quotes)
        src="${line#*SOURCE=\"}"
        src="${src%%\"*}"
        mnt="${line#*TARGET=\"}"
        mnt="${mnt%%\"*}"
        [[ -n "$src" && -n "$mnt" ]] || continue
        printf '%s\t%s\n' "$src" "$mnt"
    done < <(findmnt -P -o SOURCE,TARGET 2>/dev/null || true)
}

# The whole disk a block device ultimately sits on, printed; nothing when
# it cannot be traced (not a block device, tmpfs/overlay, or a virtual
# chain with no physical disk behind it).
#
# lsblk -s walks from the device UP through partitions to the disk -- and
# for device-mapper through its slaves too -- which PKNAME alone does not
# give (PKNAME stops at the first layer).
ci_disk_of() {
    local src="$1" name type

    # /dev/sda1[/nix/store] and friends: the [..] part is a subvolume or
    # source annotation, not a device.
    src="${src%%\[*}"
    [[ "$src" == /dev/* ]] || return 0
    [[ -b "$src" ]] || return 0

    while read -r name type; do
        [[ "$type" == "disk" ]] || continue
        printf '/dev/%s\n' "$name"
        return 0
    done < <(lsblk -s -nro NAME,TYPE "$src" 2>/dev/null)

    # A loop device reports no parent: ask for its backing file and use
    # the disk holding that file. That is how the installer media is
    # reached when the ISO is loop-mounted (booted with findiso=, for
    # example).
    if [[ "$src" == /dev/loop* ]]; then
        ci_disk_of_loop "$src"
    fi
    return 0
}

ci_disk_of_loop() {
    local loop="$1" file src tgt best_src="" best_tgt=""

    command -v losetup >/dev/null 2>&1 || return 0
    file="$(losetup -nO BACK-FILE "$loop" 2>/dev/null | head -n1 || true)"
    [[ "$file" == /* ]] || return 0

    # The file lives on some mounted filesystem; the deepest mount that
    # contains it is the one holding it.
    while IFS=$'\t' read -r src tgt; do
        [[ -n "$src" && -n "$tgt" ]] || continue
        if [[ "$tgt" == "/" ]]; then
            :
        else
            case "$file" in "$tgt"/*) ;; *) continue ;; esac
        fi
        if [[ ${#tgt} -gt ${#best_tgt} ]]; then
            best_tgt="$tgt"
            best_src="$src"
        fi
    done < <(ci_all_mounts)

    [[ -n "$best_src" ]] || return 0
    ci_disk_of "$best_src"
}

# Is $1 (a findmnt source) physically on $2 (a whole disk)?
ci_source_on_disk() {
    local src="$1" disk="$2" found

    [[ -n "$src" && -n "$disk" ]] || return 1
    found="$(ci_disk_of "$src" || true)"
    [[ -n "$found" && "$found" == "$disk" ]]
}

# Every mountpoint that ultimately sits on $1, one per line.
ci_disk_mounts() {
    local src mnt
    while IFS=$'\t' read -r src mnt; do
        [[ -n "$mnt" ]] || continue
        ci_source_on_disk "$src" "$1" && printf '%s\n' "$mnt"
    done < <(ci_all_mounts)
    return 0
}

# One-line description of a disk: size, model, transport, then the facts
# that matter for safety -- removable or not, and where its partitions are
# currently mounted. Those are what decide whether a disk is a sensible
# target and what ci_release_target has to undo first.
ci_disk_desc() {
    local dev="$1" out rm mounts

    out="$(lsblk -dnpo SIZE,MODEL,TRAN "$dev" 2>/dev/null |
        sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' || true)"
    rm="$(lsblk -dnro RM "$dev" 2>/dev/null | tr -d '[:space:]' || true)"
    mounts="$(ci_disk_mounts "$dev" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//' || true)"

    if [[ "$rm" == "1" ]]; then out="$out removable"; fi
    if [[ -n "$mounts" ]]; then out="$out mounted: $mounts"; fi

    printf '%s\n' "$out"
}

# nvme0n1 -> nvme0n1p1, sda -> sda1, vda -> vda1
ci_part_path() {
    if [[ "$1" =~ [0-9]$ ]]; then printf '%sp%s\n' "$1" "$2"; else printf '%s%s\n' "$1" "$2"; fi
}

# Disks the live environment itself came from or is running from. Never
# candidates, whatever else is true:
#
#   * whatever backs /, /iso, /nix, /boot and the read-only store
#   * any partition carrying the ISO filesystem or its label
#   * the disk that backs a loop-mounted ISO
#
# All of it resolves through ci_disk_of, so a path like
# /dev/sda2[/iso/boot] or a loop device still lands on a whole disk.
ci_installer_disks() {
    local src tgt
    {
        for tgt in / /iso /nix /nix/store /nix/.ro-store /boot /boot/efi /run/findiso; do
            findmnt -no SOURCE "$tgt" 2>/dev/null || true
        done
        lsblk -rno NAME,FSTYPE,LABEL 2>/dev/null |
            awk '$2=="iso9660" || $3 ~ /^NIXOS_ISO/ {print "/dev/"$1}' || true
    } | while read -r src; do
        [[ -n "$src" ]] || continue
        ci_disk_of "$src"
    done | sort -u
}

# Every disk that could be an installation target, as
# "device removable size_bytes" lines. Loop, ram, zram, md and floppy
# devices are never targets and are dropped here.
#
# Disks with mounted partitions are NOT dropped: those mounts are exactly
# what ci_release_target undoes before partitioning, and skipping them
# would make a re-run after a failed attempt unable to find its own disk
# (the failure this used to cause).
ci_all_disks() {
    local dev rm bytes protected
    protected=" $(ci_installer_disks | tr '\n' ' ') "

    lsblk -dprno NAME,TYPE,RM 2>/dev/null |
        awk '$2=="disk"{print $1" "$3}' |
        while read -r dev rm; do
            case "$dev" in
            /dev/zram* | /dev/loop* | /dev/ram* | /dev/fd* | /dev/md* | /dev/dm-*) continue ;;
            esac
            case "$protected" in *" $dev "*) continue ;; esac
            bytes="$(lsblk -dnbo SIZE "$dev" 2>/dev/null || printf 0)"
            [[ -n "$bytes" && "$bytes" =~ ^[0-9]+$ ]] || bytes=0
            printf '%s %s %s\n' "$dev" "$rm" "$bytes"
        done
    return 0
}

# Every probe here is advisory and must never abort the run under set -e.
# Failing to describe the disks is reported, then handled by
# ci_select_target_disk, which is the function allowed to refuse.
ci_show_disks() {
    section "Block devices"

    if ! lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,MODEL,TRAN 2>/dev/null &&
        ! lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL,TRAN 2>/dev/null &&
        ! lsblk 2>/dev/null; then
        warning "lsblk could not enumerate block devices here."
    fi

    echo
    local dev
    while read -r dev; do
        [[ -n "$dev" ]] && info "installer media / running system, protected: $dev  $(ci_disk_desc "$dev")"
    done < <(ci_installer_disks || true)
}

# Pick CI_DISK. Everything block-level is re-derived here rather than
# remembered from the listing, so what gets chosen is what the kernel
# currently reports.
ci_select_target_disk() {
    need_cmd lsblk

    local -a fixed=() removable=() small=()
    local dev rm bytes

    while read -r dev rm bytes; do
        [[ -n "$dev" ]] || continue
        # ci_all_disks already guarantees digits; anything else counts as
        # unknown-size, and unknown is not a target.
        [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
        if [[ "$bytes" -lt "$CI_MIN_DISK_BYTES" ]]; then
            small+=("$dev")
        elif [[ "$rm" == "1" ]]; then
            removable+=("$dev")
        else
            fixed+=("$dev")
        fi
    done < <(ci_all_disks || true)

    local d
    for d in ${small[@]+"${small[@]}"}; do
        info "too small for this install (needs at least 12 GiB): $d  $(ci_disk_desc "$d")"
    done

    local total=$((${#fixed[@]} + ${#removable[@]}))

    if [[ "$total" -eq 0 ]]; then
        error "No disk available for installation."
        error "The installer media and the running system's disk are protected, and"
        error "disks under 12 GiB cannot hold this configuration. Refusing to guess."
        return 1
    fi

    # Auto-selection only for exactly one fixed candidate. Anything else --
    # including a lone removable disk -- goes through the numbered table,
    # because an external USB is never chosen for the user, not even when
    # it is the only thing left.
    if [[ "${#fixed[@]}" -eq 1 && "${#removable[@]}" -eq 0 ]]; then
        CI_DISK="${fixed[0]}"
        info "Target disk: $CI_DISK  $(ci_disk_desc "$CI_DISK")"
    else
        section "Candidate disks"

        # Display order and selection order are the same array: fixed
        # disks first, removable ones after, each row labelled with the
        # class it was put in rather than re-probed for the table.
        local -a candidates=() kinds=()
        local d2
        for d2 in ${fixed[@]+"${fixed[@]}"}; do
            candidates+=("$d2")
            kinds+=("fixed")
        done
        for d2 in ${removable[@]+"${removable[@]}"}; do
            candidates+=("$d2")
            kinds+=("removable")
        done

        printf '   %b%2s%b  %-13s %-7s %-24s %-7s %-9s %s\n' \
            "$CYAN" "#" "$RESET" "DEVICE" "SIZE" "MODEL" "TRAN" "KIND" "MOUNTPOINTS"
        local i=0 size model trans mounts
        while [[ "$i" -lt "${#candidates[@]}" ]]; do
            d="${candidates[$i]}"
            size="$(lsblk -dnpo SIZE "$d" 2>/dev/null | tr -d ' ' || true)"
            model="$(lsblk -dnpo MODEL "$d" 2>/dev/null | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' || true)"
            trans="$(lsblk -dnpo TRAN "$d" 2>/dev/null | tr -d ' ' || true)"
            mounts="$(ci_disk_mounts "$d" | tr '\n' ',' | sed -E 's/,$//' || true)"
            printf '   %b%2s%b  %-13s %-7s %-24s %-7s %-9s %s\n' \
                "$CYAN" "$((i + 1))" "$RESET" "$d" "${size:-?}" "${model:-?}" \
                "${trans:-?}" "${kinds[$i]}" "${mounts:--}"
            i=$((i + 1))
        done
        echo
        local pick
        read -r -p "  Select target disk number: " pick || return 1
        if [[ ! "$pick" =~ ^[0-9]+$ ]]; then
            error "Not a number."
            return 1
        fi
        if [[ "$pick" -lt 1 || "$pick" -gt "${#candidates[@]}" ]]; then
            error "Out of range."
            return 1
        fi
        CI_DISK="${candidates[$((pick - 1))]}"
    fi

    if ci_installer_disks | grep -qxF "$CI_DISK"; then
        error "$CI_DISK holds the live environment itself (or the running system)."
        error "Refusing to use it as a target."
        return 1
    fi
    if [[ ! -b "$CI_DISK" ]]; then
        if [[ "$CI_DRY_RUN" -eq 1 ]]; then
            warning "$CI_DISK is not a block device here; continuing because this is a dry run."
        else
            error "Not a block device: $CI_DISK"
            return 1
        fi
    fi

    bytes="$(lsblk -dnbo SIZE "$CI_DISK" 2>/dev/null || printf 0)"
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    if [[ "$bytes" -lt "$CI_MIN_DISK_BYTES" ]]; then
        error "$CI_DISK is smaller than the 12 GiB floor this install needs."
        return 1
    fi
    if [[ "$bytes" -lt "$CI_WARN_DISK_BYTES" ]]; then
        warning "$CI_DISK is only $((bytes / 1073741824)) GiB; this configuration ships ~7.5 GiB of packages."
        warning "The build reserve is small; free space is checked again before it starts."
    fi

    local on_mounts
    on_mounts="$(ci_disk_mounts "$CI_DISK" | tr '\n' ' ' | sed -E 's/[[:space:]]+$//' || true)"
    if [[ -n "$on_mounts" ]]; then
        info "Partitions currently mounted on $CI_DISK (all released before partitioning):"
        info "  $on_mounts"
    fi

    # Partition 1 is the ESP in UEFI mode and the BIOS boot partition in
    # legacy mode; partition 2 is always the root filesystem.
    CI_ROOT_PART="$(ci_part_path "$CI_DISK" 2)"
    if [[ "$CI_FIRMWARE" == "UEFI" ]]; then
        CI_ESP="$(ci_part_path "$CI_DISK" 1)"
        CI_BIOS_PART=""
    else
        CI_ESP=""
        CI_BIOS_PART="$(ci_part_path "$CI_DISK" 1)"
    fi
}

# The last re-check, run after the typed confirmations and immediately
# before the disk is touched. Anything that changed in between -- a
# partition auto-mounted by the desktop, a re-plugged USB, a /mnt left
# behind by an earlier attempt on a DIFFERENT disk -- must not slip
# through on the strength of an answer given minutes earlier.
ci_verify_target_disk() {
    section "Final disk check"

    if [[ ! -b "$CI_DISK" ]]; then
        error "$CI_DISK is not a block device any more."
        return 1
    fi
    case "$CI_DISK" in
    /dev/loop* | /dev/ram* | /dev/zram* | /dev/fd* | /dev/md* | /dev/dm-*)
        error "$CI_DISK is a virtual device, not an installation target."
        return 1
        ;;
    esac
    if ci_installer_disks | grep -qxF "$CI_DISK"; then
        error "$CI_DISK holds the live environment itself (or the running system)."
        error "Refusing to erase it."
        return 1
    fi

    local bytes
    bytes="$(lsblk -dnbo SIZE "$CI_DISK" 2>/dev/null || printf 0)"
    if [[ ! "$bytes" =~ ^[0-9]+$ ]] || [[ "$bytes" -lt "$CI_MIN_DISK_BYTES" ]]; then
        error "$CI_DISK reports ${bytes} bytes; below the 12 GiB this install needs."
        return 1
    fi

    # A mount left on /mnt from a previous attempt on the SAME disk is
    # what ci_release_target exists to undo. A mount from anywhere else
    # means something unrelated is in the way.
    if mountpoint -q "$CI_TARGET" 2>/dev/null; then
        local src
        src="$(findmnt -no SOURCE "$CI_TARGET" 2>/dev/null || true)"
        if ! ci_source_on_disk "$src" "$CI_DISK"; then
            error "$CI_TARGET is mounted from ${src:-unknown}, which is not on $CI_DISK."
            error "Refusing to stack a new install on top of an unrelated mount."
            return 1
        fi
        info "$CI_TARGET is mounted from $CI_DISK; the release step will unmount it."
    fi

    success "Target re-checked: $CI_DISK is safe to erase ($CI_FIRMWARE layout, $(ci_disk_desc "$CI_DISK"))."
    return 0
}

# What the error panel shows: where we were, what is mounted, what swap is
# active. Everything guarded; this must never fail while reporting a failure.
ci_state_report() {
    printf '\n'
    info "Installer state:"
    printf '  phase    : %s\n' "${CI_PHASE:-init}"
    printf '  firmware : %s\n' "${CI_FIRMWARE:-undetected}"
    printf '  disk     : %s\n' "${CI_DISK:-not selected}"
    printf '  target   : %s\n' "$CI_TARGET"
    printf '  command  : %s\n' "${1:-n/a}"
    printf '  at line  : %s in %s\n' "${2:-?}" "${3:-?}"
    echo
    info "Mounts under $CI_TARGET (findmnt -R):"
    if [[ -n "$(findmnt -R "$CI_TARGET" 2>/dev/null || true)" ]]; then
        findmnt -R "$CI_TARGET" 2>/dev/null | sed 's/^/    /' || true
    else
        printf '    (none)\n'
    fi
    echo
    info "Active swap (swapon --show):"
    if [[ -n "$(swapon --show=NAME --noheadings 2>/dev/null || true)" ]]; then
        swapon --show 2>/dev/null | sed 's/^/    /' || true
    else
        printf '    (none)\n'
    fi
    echo
    info "Diagnose with:  findmnt -R $CI_TARGET ; lsblk ; swapon --show"
}

# The ERR trap body. Armed by ci_install_entry for the whole install run.
# Re-entry guard first: ci_teardown_swap failing inside the handler must not
# recurse through the trap again.
ci_on_error() {
    if [[ "$CI_IN_ERR" -eq 1 ]]; then exit 1; fi
    CI_IN_ERR=1
    trap - ERR

    local line="${1:-?}" cmd="${2:-?}" func="${3:-main}"

    echo
    error "Clean installation stopped."
    printf '  %b%s%b failed at line %s in %s\n' "$RED" "$cmd" "$RESET" "$line" "$func"

    ci_state_report "$cmd" "$line" "$func" || true
    ci_teardown_swap || true

    case "$CI_PHASE" in
    preflight | identity | review)
        warning "Nothing was changed on the disk."
        info "Fix the problem above and re-run: ./setup.sh clean-install"
        ;;
    destructive)
        warning "The disk HAS been modified. The target stays at $CI_TARGET for inspection."
        info "Re-running ./setup.sh clean-install is safe: the release step clears this attempt."
        ;;
    configure | install)
        warning "The target stays mounted at $CI_TARGET for inspection."
        info "Re-run ./setup.sh clean-install to start over from a clean release."
        ;;
    verify)
        warning "Fix the failures printed above, then re-check with ./setup.sh verify-boot."
        warning "Do not reboot expecting the new configuration yet."
        ;;
    *)
        warning "The target stays at $CI_TARGET for inspection."
        ;;
    esac

    exit 1
}

# The only entry point for a real install (menu, CLI, install_flow redirect).
#
# Called BARE from every site: a tested call site (cmd || true) would suspend
# errexit and the ERR trap for the entire run below it, which is exactly the
# bug this structure exists to prevent. The wrapper arms the trap, runs
# clean_install bare, and clears the trap when -- and only when -- it
# returns 0 (success or user abort).
ci_install_entry() {
    local arg="${1:-}"

    # Reject a bad command line HERE, before the ERR trap is armed: a typo
    # in an option is a usage message and exit 2, not the failure panel
    # that an aborted installation would produce.
    case "$arg" in
    "" | --dry-run | -n) ;;
    *)
        error "Unknown option for clean-install: $arg"
        info "Usage: ./setup.sh clean-install [--dry-run]"
        return 2
        ;;
    esac

    CI_IN_ERR=0
    CI_STARTED_DESTRUCTIVE=0
    CI_PHASE="init"
    trap 'ci_on_error "$LINENO" "$BASH_COMMAND" "${FUNCNAME[0]:-main}"' ERR
    clean_install "$arg"
    trap - ERR
    return 0
}

# The last gate before anything is touched: the review screen, then the two
# typed confirmations from the specification. Both must be typed exactly.
# Returns 1 only as "user said no" -- clean_install turns that into a
# clean return 0 to the menu.
ci_confirm_destroy() {
    section "Target review"
    printf '  Device    : %s  %s\n' "$CI_DISK" "$(ci_disk_desc "$CI_DISK")"
    printf '  Firmware  : %s\n' "$CI_FIRMWARE"
    if [[ -n "$(lsblk -lnpo NAME "$CI_DISK" 2>/dev/null | sed -n '2,$p' || true)" ]]; then
        printf '  Existing partitions:\n'
        lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS "$CI_DISK" 2>/dev/null | sed 's/^/    /' || true
    else
        printf '  Existing  : no partitions\n'
    fi
    printf '  New layout:\n'
    if [[ "$CI_FIRMWARE" == "UEFI" ]]; then
        printf '    %-14s %6s  %-6s label=%-5s -> %s/boot\n' \
            "$CI_ESP" "1GiB" "fat32" "$CI_ESP_LABEL" "$CI_TARGET"
        printf '    %-14s %6s  %-6s label=%-5s -> %s\n' \
            "$CI_ROOT_PART" "rest" "ext4" "$CI_ROOT_LABEL" "$CI_TARGET"
    else
        printf '    %-14s %6s  %-6s BIOS boot partition (GRUB core, no filesystem)\n' \
            "$CI_BIOS_PART" "2MiB" "-"
        printf '    %-14s %6s  %-6s label=%-5s -> %s\n' \
            "$CI_ROOT_PART" "rest" "ext4" "$CI_ROOT_LABEL" "$CI_TARGET"
    fi
    echo
    hr
    warning "EVERY PARTITION ON $CI_DISK WILL BE ERASED."
    hr
    echo

    local attempt answer
    for attempt in 1 2 3; do
        read -r -p "  Type ERASE $CI_DISK to continue: " answer || {
            echo
            return 1
        }
        if [[ "$answer" == "ERASE $CI_DISK" ]]; then break; fi
        if [[ "$attempt" -eq 3 ]]; then
            warning "Did not match. Aborted."
            return 1
        fi
        warning "Type exactly: ERASE $CI_DISK"
    done

    for attempt in 1 2 3; do
        read -r -p "  Type INSTALL SUNFLOWER to continue: " answer || {
            echo
            return 1
        }
        if [[ "$answer" == "INSTALL SUNFLOWER" ]]; then break; fi
        if [[ "$attempt" -eq 3 ]]; then
            warning "Did not match. Aborted."
            return 1
        fi
        warning "Type exactly: INSTALL SUNFLOWER"
    done
    echo
}

# Every mount whose source ultimately sits on $CI_DISK, as "source<TAB>target"
# lines, deepest mount last (callers sort). This is the single authority for
# "is the target disk free?": it catches /mnt, its children, and any stray
# mount of a partition or mapper device that traces back to the disk -- the
# parent walk in ci_disk_of covers partitions and device-mapper layers, and
# a bind mount like /dev/sda1[/subvol] matches after the [..] suffix is
# stripped.
ci_mounts_of_disk() {
    local src mnt
    while IFS=$'\t' read -r src mnt; do
        [[ -n "$mnt" ]] || continue
        if ci_source_on_disk "$src" "$CI_DISK"; then
            printf '%s\t%s\n' "$src" "$mnt"
        fi
    done < <(ci_all_mounts)
    return 0
}

# Return the disk to a completely unmounted, swap-free state before
# repartitioning it. A rerun after a failed attempt lands here, which is what
# makes "just run it again" safe.
#
# The unmount list is the union of two things: mounts that trace back to
# $CI_DISK, and mounts whose TARGET lies under $CI_TARGET. The second set is
# not redundant -- an attempt made against a different disk can leave /mnt
# mounted from elsewhere, and stacking a new install on top of it would be
# exactly the silent failure this step exists to prevent.
ci_release_target() {
    section "Releasing target"

    # Swap first: a mounted-onto swapfile is not a mount, findmnt will not
    # show it, and mkfs under active swap is how disks get corrupted.
    local s own
    while read -r s; do
        [[ -n "$s" ]] || continue
        own=""
        if [[ -f "$s" ]]; then
            # Only swap files we are responsible for: under CI_TARGET, or
            # the one the installer itself created.
            case "$s" in
            "$CI_TARGET"/*) own=1 ;;
            esac
        elif [[ "$s" == /dev/* ]]; then
            if [[ "$s" == "$CI_DISK" ]] || [[ "$(ci_disk_of "$s" || true)" == "$CI_DISK" ]]; then
                own=1
            fi
        fi
        [[ -n "$own" ]] || continue
        info "swapoff $s"
        swapoff "$s" 2>/dev/null || {
            error "Could not disable swap: $s"
            return 1
        }
    done < <(swapon --show=NAME --noheadings 2>/dev/null || true)

    # Union of the two sets above, deepest path first so parents come after
    # their children.
    local lines attempt src mnt
    lines="$(
        {
            ci_mounts_of_disk
            while IFS=$'\t' read -r src mnt; do
                [[ -n "$mnt" ]] || continue
                case "$mnt" in
                "$CI_TARGET" | "$CI_TARGET"/*) printf '%s\t%s\n' "$src" "$mnt" ;;
                esac
            done < <(ci_all_mounts)
        } | sort -u | awk -F'\t' '{ print length($2), $0 }' | sort -rn | cut -d' ' -f2- || true
    )"

    if [[ -z "$lines" ]]; then
        success "Nothing on $CI_DISK is mounted."
        ci_assert_released
        return $?
    fi

    while IFS=$'\t' read -r src mnt; do
        [[ -n "$mnt" ]] || continue
        for attempt in 1 2 3; do
            info "umount $mnt (attempt $attempt/3)"
            if umount "$mnt" 2>/dev/null; then break; fi
            sleep 1
        done
        if findmnt -rn -T "$mnt" 2>/dev/null | grep -qF "$mnt"; then
            error "Could not unmount $mnt (source $src)."
            warning "Refusing to repartition a disk that is still in use."
            findmnt -R "$CI_TARGET" 2>/dev/null || true
            return 1
        fi
    done <<<"$lines"

    ci_assert_released
}

# The final authority check, not a spot check: nothing left on the disk and
# /mnt itself not mounted from anywhere.
ci_assert_released() {
    local still
    still="$(ci_mounts_of_disk)"
    if [[ -n "$still" ]]; then
        error "Parts of $CI_DISK are still mounted:"
        printf '%s\n' "$still" | sed 's/^/    /'
        return 1
    fi
    if mountpoint -q "$CI_TARGET" 2>/dev/null; then
        error "$CI_TARGET is still mounted from $(findmnt -no SOURCE "$CI_TARGET" 2>/dev/null || echo unknown)."
        return 1
    fi
    success "Target released: no mounts, no swap on $CI_DISK."
    return 0
}

ci_wait_for_part() {
    if [[ "$CI_DRY_RUN" -eq 1 ]]; then return 0; fi

    local p="$1" i=0

    while [[ ! -b "$p" ]]; do
        i=$((i + 1))
        if [[ "$i" -gt 60 ]]; then
            error "Partition never appeared: $p"
            return 1
        fi
        sleep 0.1
        udevadm settle >/dev/null 2>&1 || true
    done
}

# Read PARTTYPE straight from the device (libblkid, no udev cache involved).
ci_part_type() {
    lsblk -dnro PARTTYPE "$1" 2>/dev/null | tr -d '[:space:]' || true
}

ci_partition() {
    section "Partitioning $CI_DISK ($CI_FIRMWARE)"

    local root_start="1025MiB"
    if [[ "$CI_FIRMWARE" != "UEFI" ]]; then root_start="3MiB"; fi

    ci_run wipefs -a "$CI_DISK"

    # Both partitioners, both firmware modes: GPT, partition 1 tiny and typed
    # for boot, partition 2 the rest of the disk as Linux filesystem.
    if [[ "$CI_PARTITIONER" == "parted" ]]; then
        ci_run parted -s "$CI_DISK" mklabel gpt
        if [[ "$CI_FIRMWARE" == "UEFI" ]]; then
            ci_run parted -s "$CI_DISK" mkpart "$CI_ESP_LABEL" fat32 1MiB 1025MiB
            ci_run parted -s "$CI_DISK" set 1 esp on
        else
            ci_run parted -s "$CI_DISK" mkpart BIOSBOOT 1MiB 3MiB
            ci_run parted -s "$CI_DISK" set 1 bios_grub on
        fi
        ci_run parted -s "$CI_DISK" mkpart "$CI_ROOT_LABEL" ext4 "$root_start" 100%
    else
        ci_run sgdisk --zap-all "$CI_DISK"
        if [[ "$CI_FIRMWARE" == "UEFI" ]]; then
            ci_run sgdisk \
                --new=1:1M:1025M --typecode=1:ef00 --change-name=1:"$CI_ESP_LABEL" \
                --new=2:0:0 --typecode=2:8300 --change-name=2:"$CI_ROOT_LABEL" \
                "$CI_DISK"
        else
            ci_run sgdisk \
                --new=1:1M:3M --typecode=1:ef02 --change-name=1:BIOSBOOT \
                --new=2:0:0 --typecode=2:8300 --change-name=2:"$CI_ROOT_LABEL" \
                "$CI_DISK"
        fi
    fi

    # partprobe ships with parted and udevadm with systemd; neither is worth
    # requiring, because ci_wait_for_part is what actually guarantees the nodes.
    if command -v partprobe >/dev/null 2>&1; then
        ci_run partprobe "$CI_DISK" || true
    fi
    if command -v udevadm >/dev/null 2>&1; then
        ci_run udevadm settle || true
    fi

    ci_wait_for_part "$CI_ROOT_PART" || return 1

    # The partition table itself is verified before anything is formatted:
    # a wrong type here means the partitioner did something unexpected.
    local want_p1
    if [[ "$CI_FIRMWARE" == "UEFI" ]]; then
        ci_wait_for_part "$CI_ESP" || return 1
        want_p1="$CI_PTYPE_EFI"
    else
        ci_wait_for_part "$CI_BIOS_PART" || return 1
        want_p1="$CI_PTYPE_BIOS"
    fi

    if [[ "$(ci_part_type "$CI_ROOT_PART")" != "$CI_PTYPE_LINUX" ]]; then
        error "Partition 2 on $CI_DISK has an unexpected type: $(ci_part_type "$CI_ROOT_PART")"
        return 1
    fi

    local p1="${CI_ESP:-$CI_BIOS_PART}"
    if [[ "$(ci_part_type "$p1")" != "$want_p1" ]]; then
        error "Partition 1 on $CI_DISK has an unexpected type: $(ci_part_type "$p1")"
        return 1
    fi

    success "GPT written by $CI_PARTITIONER ($CI_FIRMWARE): boot partition 1, $CI_ROOT_LABEL root on partition 2."
}

ci_format() {
    section "Formatting"

    # Nothing from this disk may be mounted while mkfs runs. Not a spot
    # check: the same authority the release step used.
    local still
    still="$(ci_mounts_of_disk)"
    if [[ -n "$still" ]]; then
        error "Refusing to format; parts of $CI_DISK are mounted:"
        printf '%s\n' "$still" | sed 's/^/    /'
        return 1
    fi

    if [[ "$CI_FIRMWARE" == "UEFI" ]]; then
        if ! ci_run "$CI_MKFS_FAT" -F32 -n "$CI_ESP_LABEL" "$CI_ESP"; then
            error "Failed to format EFI partition: $CI_ESP"
            return 1
        fi
    fi

    if ! ci_run mkfs.ext4 -F -L "$CI_ROOT_LABEL" "$CI_ROOT_PART"; then
        error "Failed to format root partition: $CI_ROOT_PART"
        return 1
    fi

    if [[ "$CI_DRY_RUN" -eq 0 ]]; then
        # -p: probe the device directly, never the blkid cache, which may
        # still hold the pre-format answer.
        if [[ "$CI_FIRMWARE" == "UEFI" ]]; then
            local esp_type esp_label
            esp_type="$(blkid -p -o value -s TYPE "$CI_ESP" 2>/dev/null || true)"
            esp_label="$(blkid -p -o value -s LABEL "$CI_ESP" 2>/dev/null || true)"
            if [[ "$esp_type" != "vfat" ]]; then
                error "EFI partition is not vfat after formatting (got '${esp_type:-nothing}')."
                return 1
            fi
            if [[ "$esp_label" != "$CI_ESP_LABEL" ]]; then
                error "EFI partition label is '$esp_label', expected $CI_ESP_LABEL."
                return 1
            fi
        fi

        local root_type root_label
        root_type="$(blkid -p -o value -s TYPE "$CI_ROOT_PART" 2>/dev/null || true)"
        root_label="$(blkid -p -o value -s LABEL "$CI_ROOT_PART" 2>/dev/null || true)"
        if [[ "$root_type" != "ext4" ]]; then
            error "Root partition is not ext4 after formatting (got '${root_type:-nothing}')."
            return 1
        fi
        if [[ "$root_label" != "$CI_ROOT_LABEL" ]]; then
            error "Root partition label is '$root_label', expected $CI_ROOT_LABEL."
            return 1
        fi
    fi

    success "Filesystems created ($CI_FIRMWARE layout)."
}

ci_mount() {
    section "Mounting"

    ci_run mkdir -p "$CI_TARGET"
    ci_run mount "$CI_ROOT_PART" "$CI_TARGET"

    if [[ "$CI_FIRMWARE" == "UEFI" ]]; then
        ci_run mkdir -p "$CI_TARGET/boot"
        ci_run mount "$CI_ESP" "$CI_TARGET/boot"
    fi

    if [[ "$CI_DRY_RUN" -eq 0 ]]; then
        if ! mountpoint -q "$CI_TARGET"; then
            error "$CI_TARGET is not a mountpoint."
            return 1
        fi
        if [[ "$(findmnt -no FSTYPE "$CI_TARGET")" != "ext4" ]]; then
            error "$CI_TARGET is not ext4."
            return 1
        fi

        if [[ "$CI_FIRMWARE" == "UEFI" ]]; then
            if ! mountpoint -q "$CI_TARGET/boot"; then
                error "$CI_TARGET/boot is not a mountpoint."
                return 1
            fi
            if [[ "$(findmnt -no FSTYPE "$CI_TARGET/boot")" != "vfat" ]]; then
                error "$CI_TARGET/boot is not vfat."
                return 1
            fi
        fi

        lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS "$CI_DISK" 2>/dev/null || lsblk "$CI_DISK" || true
        df -h "$CI_TARGET" || true
    fi

    success "Mounted ($CI_FIRMWARE)."
}

# Install-time swap and scratch space on the target.
#
# The writable layer of the ISO's /nix/store is a tmpfs, so every path this
# build downloads or produces is held in RAM until nixos-install copies it to
# the target. A closure this size, Hyprland and Quickshell and Neovim and
# Stylix and the font set, is a well known way to run a live installer out of
# memory partway through.
#
# Swap on the freshly mounted target lets that tmpfs spill to disk instead,
# and TMPDIR on the target keeps nix's own temporaries there too (nixos-install
# honours an inherited TMPDIR). Both exist only for the install and are
# removed afterwards, so hardware-configuration.nix keeps swapDevices = [ ]
# and nothing is left behind.
ci_setup_swap() {
    section "Install-time swap"

    if [[ "$CI_DRY_RUN" -eq 1 ]]; then
        run_cmd "fallocate + mkswap + swapon $CI_TARGET/.setup-swapfile"
        run_cmd "TMPDIR=$CI_TARGET/.setup-tmp"
        info "Both removed again once the install finishes."
        return 0
    fi

    export TMPDIR="$CI_TARGET/.setup-tmp"
    mkdir -p "$TMPDIR"

    # Size is derived from what is free AFTER the build reserve:
    # swap may take a quarter of free space, up to 8 GiB, and may never
    # push free space below CI_BUILD_RESERVE_GB. Nix needs that room for
    # the store and its temporaries -- swap that eats into it just moves
    # the failure from OOM to ENOSPC, later and with less information.
    local avail_kb reserve_kb swap_kb size_g
    avail_kb="$(df -Pk "$CI_TARGET" | awk 'NR==2{print $4}')"
    [[ "$avail_kb" =~ ^[0-9]+$ ]] || avail_kb=0
    reserve_kb=$((CI_BUILD_RESERVE_GB * 1024 * 1024))

    if [[ $((avail_kb - reserve_kb)) -lt $((2 * 1024 * 1024)) ]]; then
        v_info "less than 2 GiB above the ${CI_BUILD_RESERVE_GB} GiB build reserve; continuing without install-time swap"
        return 0
    fi

    swap_kb=$((avail_kb / 4))
    if [[ "$swap_kb" -gt $((8 * 1024 * 1024)) ]]; then swap_kb=$((8 * 1024 * 1024)); fi
    if [[ $((avail_kb - swap_kb)) -lt "$reserve_kb" ]]; then
        swap_kb=$((avail_kb - reserve_kb))
    fi
    size_g=$((swap_kb / 1024 / 1024))
    if [[ "$size_g" -lt 1 ]]; then
        v_info "too little free space for install-time swap; continuing without it"
        return 0
    fi

    local f="$CI_TARGET/.setup-swapfile"

    if ! fallocate -l "${size_g}G" "$f" 2>/dev/null; then
        if ! dd if=/dev/zero of="$f" bs=1M count=$((size_g * 1024)) status=none 2>/dev/null; then
            v_info "could not create a swapfile; continuing without it"
            rm -f "$f"
            return 0
        fi
    fi

    chmod 600 "$f"

    if mkswap "$f" >/dev/null 2>&1 && swapon "$f" 2>/dev/null; then
        CI_SWAPFILE="$f"
        success "${size_g} GiB install-time swap active; $(((avail_kb - swap_kb) / 1024)) MiB left free for the build."
    else
        v_info "could not enable swap; continuing without it"
        rm -f "$f"
    fi
}

# The last free-space question, asked after mount and swap and immediately
# before the build starts: everything that will consume space is now in
# place, so this is the honest number. Fill the store half-way through and
# the failure surfaces as an ENOSPC from deep inside a build; refuse here
# and it surfaces as one clear message with the disk still intact.
ci_check_space() {
    section "Free space"

    local avail_kb reserve_kb ram_kb
    avail_kb="$(df -Pk "$CI_TARGET" | awk 'NR==2{print $4}')"
    [[ "$avail_kb" =~ ^[0-9]+$ ]] || avail_kb=0
    reserve_kb=$((CI_BUILD_RESERVE_GB * 1024 * 1024))

    info "target free: $((avail_kb / 1024)) MiB; build reserve: $CI_BUILD_RESERVE_GB GiB"

    if [[ "$avail_kb" -lt "$reserve_kb" ]]; then
        error "only $((avail_kb / 1024)) MiB free on $CI_TARGET, below the ${CI_BUILD_RESERVE_GB} GiB the build needs."
        error "Refusing to start a build that would run the store out of space."
        if [[ "$avail_kb" -lt $((2 * 1024 * 1024)) ]]; then
            info "This disk is too small for this configuration; a larger one is needed."
        fi
        return 1
    fi

    ram_kb="$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null || printf 0)"
    if [[ "$ram_kb" -gt 0 && "$ram_kb" -lt $((4 * 1024 * 1024)) ]]; then
        warning "RAM is only $((ram_kb / 1024)) MiB; the build will lean hard on install-time swap."
    fi

    success "Space check passed: $((avail_kb / 1024)) MiB free with the reserve intact."
    return 0
}

# Idempotent and quiet when there is nothing to do: this runs from the EXIT
# trap on every possible exit path, including early dies before the install
# ever started.
ci_teardown_swap() {
    local did=0

    if [[ -n "$CI_SWAPFILE" ]]; then
        swapoff "$CI_SWAPFILE" 2>/dev/null || true
        rm -f "$CI_SWAPFILE"
        CI_SWAPFILE=""
        did=1
    fi

    if [[ -n "${TMPDIR:-}" && "$TMPDIR" == "$CI_TARGET/.setup-tmp" ]]; then
        rm -rf "$TMPDIR" 2>/dev/null || true
        unset TMPDIR
        did=1
    fi

    if [[ "$did" -eq 1 && "${CI_IN_ERR:-0}" -eq 0 ]]; then
        info "Install-time swap and scratch space removed."
    fi
    return 0
}

# The other half of the EXIT-trap cleanup: every scratch directory the
# build itself created, plus a leftover swapfile from an attempt that died
# before CI_SWAPFILE was ever set. Idempotent, and only after the
# destructive phase has actually started.
ci_cleanup_build_dirs() {
    if [[ "${CI_STARTED_DESTRUCTIVE:-0}" -ne 1 ]]; then return 0; fi
    rm -rf "$CI_TARGET/.setup-tmp" "$CI_TARGET/.nix-cache" "$CI_TARGET/.nix-tmp" \
        "$CI_TARGET/.nixos-build-swap" 2>/dev/null || true
    # A previous failed attempt's swapfile: off first if still on, then gone.
    if [[ -f "$CI_TARGET/.setup-swapfile" ]]; then
        swapoff "$CI_TARGET/.setup-swapfile" 2>/dev/null || true
        rm -f "$CI_TARGET/.setup-swapfile" 2>/dev/null || true
    fi
    return 0
}

# Copy this checkout onto the target. Always a copy, never a clone: the
# script IS the checkout being run from, including any uncommitted work.
#
# The copy goes into place as root while nix builds (root owns the tree git
# and nix will read), and is chowned back to the real user at the end.
ci_place_repo() {
    section "Repository"

    CI_DEST="$CI_TARGET/home/$CI_USER/$REPO_NAME"
    ci_run mkdir -p "$CI_DEST"

    info "Copying this checkout (history and uncommitted work included)."
    if ! cp -a "$ROOT/." "$CI_DEST/"; then
        error "Could not copy the repository to $CI_DEST"
        return 1
    fi

    rm -rf "$CI_DEST/.setup-backups"

    if [[ ! -f "$CI_DEST/flake.nix" ]]; then
        error "No flake.nix at $CI_DEST"
        return 1
    fi
    if [[ ! -d "$CI_DEST/$HOST_DIR" ]]; then
        error "No $HOST_DIR in the copied repository at $CI_DEST"
        return 1
    fi

    # A flake named as a directory that contains .git is fetched as a git
    # tree: only what the index knows about is visible to the build, and a
    # foreign owner makes git refuse the repository as dubious.
    #
    # Whether to keep .git at all was decided by ci_validate_config_copy:
    # CI_STRIP_GIT=1 means the flake was proven to evaluate only as a plain
    # path (or there was never a .git to keep), and a plain path sees every
    # file regardless of git state. With no decision on record, fall back
    # to a health check -- keep it only if it is a real repository whose
    # index, once staged, covers the tree.
    if [[ -d "$CI_DEST/.git" ]]; then
        if command -v git >/dev/null 2>&1; then
            git config --global --add safe.directory "$CI_DEST" 2>/dev/null || true
        fi

        if [[ "${CI_STRIP_GIT:-}" == "1" ]]; then
            info "Dropping .git: the configuration was validated as a plain path."
            rm -rf "$CI_DEST/.git"
        elif command -v git >/dev/null 2>&1 &&
            git -C "$CI_DEST" rev-parse --git-dir >/dev/null 2>&1; then
            if ! git -C "$CI_DEST" add -A >/dev/null 2>&1; then
                warning "git add -A failed; untracked files would be invisible to the flake."
                warning "Dropping .git so the flake sees every file as a plain path."
                rm -rf "$CI_DEST/.git"
            else
                info ".git kept: staged, so every file on disk is visible to the flake."
            fi
        else
            info "Dropping .git: not a usable repository here (or git is absent)."
            rm -rf "$CI_DEST/.git"
        fi
    fi

    ci_run chown -R 0:0 "$CI_DEST"

    success "Repository at $CI_DEST"
}

# Identity is collected and applied in two separate steps, on purpose.
#
# Collecting happens before anything on disk is touched, so every question is
# answered before the destructive part begins. Applying happens after the
# repository has been placed, because the file that must be edited is the copy
# inside the target, not the one on the USB.
#
# They were one step before, which was a bug: the destination path is derived
# from the username, so changing the username at the prompt left the
# repository under the old name while ownership was fixed on the new one.

CI_ID_KEYS=(username name hostname gitUser email timezone locale)
declare -A CI_ID=()

ci_ask() {
    local key="$1" label="$2" def="${3:-}" regex="${4:-}" validator="${5:-}" val

    while true; do
        if [[ -n "$def" ]]; then
            read -r -p "  $label [$def]: " val || {
                echo
                return 1
            }
            val="${val:-$def}"
        else
            read -r -p "  $label: " val || {
                echo
                return 1
            }
        fi

        if [[ -z "$val" ]]; then
            warning "Cannot be empty."
            continue
        fi
        if [[ -n "$regex" ]] && ! [[ "$val" =~ $regex ]]; then
            warning "Invalid $label: $val"
            continue
        fi
        # Values land inside a Nix double-quoted string; a quote or a
        # backslash in the answer would terminate it early and produce a
        # file that does not parse. Refuse them at the prompt instead.
        if [[ "$val" == *'"'* || "$val" == *\\* ]]; then
            warning "$label cannot contain quotes or backslashes."
            continue
        fi
        # Per-key extra rules (reserved names, RFC shape, e-mail syntax).
        # The validator prints its own reason; the prompt repeats.
        if [[ -n "$validator" ]] && ! "$validator" "$val"; then
            continue
        fi

        CI_ID["$key"]="$val"
        return 0
    done
}

# ---- identity validators -------------------------------------------------
#
# Everything the questionnaire accepts passes through one of these before it
# can reach lib/variables.nix. They never modify their argument; hostname
# lowercasing lives in ci_normalize_hostname so there is exactly one place
# that decides what a hostname becomes.

# Reserved or already-taken account names: users.users.<name>.isNormalUser
# on top of an existing system account is a NixOS evaluation conflict, and
# 'root' would put a normal-user shell on uid 0.
ci_username_ok() {
    local u="$1"

    if [[ ${#u} -gt 32 ]]; then
        warning "Username too long (32 characters maximum)."
        return 1
    fi
    if [[ "$u" == *- ]]; then
        warning "Username cannot end with '-'."
        return 1
    fi
    case "$u" in
    root | nobody | daemon | bin | sys | sync | halt | shutdown | operator | list | proxy | news | mail)
        warning "Username '$u' is reserved by the system."
        return 1
        ;;
    esac
    return 0
}

# One @, non-empty sides, no spaces. Deliberately not a full RFC 5322
# parser: this address ends up in git's user.email and nothing else.
ci_email_ok() {
    local e="$1"

    if [[ "$e" == *[[:space:]]* ]]; then
        warning "Email cannot contain spaces."
        return 1
    fi
    if [[ "$e" != *@* || "$e" == @* || "$e" == *@ ]]; then
        warning "Not a valid email address: $e"
        return 1
    fi
    if [[ "${e#*@}" == *"@"* ]]; then
        warning "Not a valid email address (more than one @): $e"
        return 1
    fi
    return 0
}

# RFC 1123 shape: labels of 1-63 letters/digits/hyphens, joined by dots,
# whole thing at most 253 characters, no leading/trailing dot or hyphen.
# Only [A-Za-z0-9.-] can appear at all, so no shell metacharacter, no
# slash, no space and no path traversal ever gets past this.
ci_hostname_ok() {
    local h="$1" label

    [[ -n "$h" ]] || return 1
    [[ ${#h} -le 253 ]] || return 1
    [[ "$h" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
    [[ "$h" != .* && "$h" != *. && "$h" != *..* ]] || return 1

    local IFS=.
    for label in $h; do
        [[ -n "$label" ]] || return 1
        [[ ${#label} -le 63 ]] || return 1
        [[ "$label" != -* && "$label" != *- ]] || return 1
    done
    return 0
}

# Print the hostname to use on stdout; return 1 with the reason on stderr
# when the input cannot be salvaged. Uppercase is normalised to lowercase
# with a notice rather than silently accepted -- never in a direction the
# user did not see, and never while leaving invalid input through.
ci_normalize_hostname() {
    local h="$1"

    if [[ "$h" =~ [[:space:]] ]]; then
        warning "Hostname cannot contain spaces." >&2
        return 1
    fi
    if ! ci_hostname_ok "$h"; then
        warning "Invalid hostname: '$h'." >&2
        info "RFC 1123 only: letters, digits, dots and hyphens; each label 1-63" >&2
        info "characters without a leading or trailing hyphen; at most 253 total." >&2
        return 1
    fi
    if [[ "$h" == *[A-Z]* ]]; then
        h="${h,,}"
        warning "Hostnames are lowercase; using '$h'." >&2
    fi
    printf '%s' "$h"
}

# The hostname question, on its own because it is the one answer that is
# rewritten (lowercased) and the one that must never be validated loosely.
ci_ask_hostname() {
    local def="$1" val

    # Show the default in the form that would actually be used: the stored
    # value may be mixed case, and answering Enter yields the lowercase
    # spelling. A default that cannot be salvaged becomes no default at
    # all, rather than a trap that rejects the answer just accepted.
    if [[ -n "$def" ]]; then
        def="$(ci_normalize_hostname "$def" 2>/dev/null || true)"
    fi

    while true; do
        if [[ -n "$def" ]]; then
            read -r -p "  Hostname [$def]: " val || {
                echo
                return 1
            }
            val="${val:-$def}"
        else
            read -r -p "  Hostname: " val || {
                echo
                return 1
            }
        fi

        # Trim surrounding whitespace, then let ci_normalize_hostname be the
        # single authority on what is legal.
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"

        if [[ -z "$val" ]]; then
            warning "Cannot be empty."
            continue
        fi
        if [[ "$val" == *'"'* || "$val" == *\\* ]]; then
            warning "Hostname cannot contain quotes or backslashes."
            continue
        fi
        if ! val="$(ci_normalize_hostname "$val")"; then
            continue
        fi

        CI_ID[hostname]="$val"
        return 0
    done
}

# zoneinfo lives at /usr/share/zoneinfo on most distributions but behind
# /etc/zoneinfo on NixOS (both the live ISO and the installed system), so
# checking only the usual path never fires here at all.
ci_zoneinfo_dir() {
    local d
    for d in /etc/zoneinfo /usr/share/zoneinfo; do
        if [[ -d "$d" ]]; then
            printf '%s' "$d"
            return 0
        fi
    done
    return 1
}

# PCI display adapters as PCI:<bus>@<domain>:<dev>:<func>, decimal, which is
# exactly what modules/nvidia expects (nixpkgs busIDType). lspci -Dn prints
# the address in hex with dots; convert rather than hand the user a guess.
ci_detect_gpu_busids() {
    CI_GPU_INTEL=""
    CI_GPU_NVIDIA=""
    command -v lspci >/dev/null 2>&1 || return 0

    local addr cls vend rest dom bus dev func val
    while read -r addr cls vend; do
        [[ "$cls" == 03* ]] || continue # class 03xx: display controllers
        [[ "$addr" == *:*:*.* ]] || continue

        dom="${addr%%:*}"
        rest="${addr#*:}"
        bus="${rest%%:*}"
        rest="${rest#*:}"
        dev="${rest%%.*}"
        func="${rest#*.}"

        val="PCI:$((16#$bus))@$((16#$dom)):$((16#$dev)):$((16#$func))"

        case "$vend" in
        10de:*)
            CI_GPU_NVIDIA="$val"
            ;;
        8086:* | 1002:*)
            if [[ -z "$CI_GPU_INTEL" ]]; then CI_GPU_INTEL="$val"; fi
            ;;
        esac
    done < <(lspci -Dn 2>/dev/null | awk '{print $1, $2, $3}')
    return 0
}

ci_collect_identity() {
    section "Identity"
    info "Asked now, before anything on disk is touched."
    info "Defaults come from lib/variables.nix -- never from this live session,"
    info "whose hostname and user say nothing about the machine being installed."

    local cur k
    for k in "${CI_ID_KEYS[@]}"; do
        cur="$(sed -nE "s/^[[:space:]]*${k}[[:space:]]*=[[:space:]]*\"([^\"]*)\";.*/\1/p" "$VARS" | head -n1 || true)"
        case "$k" in
        username)
            ci_ask "$k" "Username" "$cur" '^[a-z_][a-z0-9_-]*$' ci_username_ok || return 1
            ;;
        hostname)
            # Its own loop: RFC shape plus lowercase normalisation, neither
            # of which ci_ask's flat regex can express.
            ci_ask_hostname "$cur" || return 1
            ;;
        name)
            ci_ask "$k" "Full name" "$cur" || return 1
            ;;
        gitUser)
            ci_ask "$k" "Git username" "$cur" || return 1
            ;;
        email)
            ci_ask "$k" "Git email" "$cur" '' ci_email_ok || return 1
            ;;
        timezone)
            ci_ask "$k" "Timezone" "$cur" || return 1
            ;;
        locale)
            ci_ask "$k" "Locale" "$cur" || return 1
            ;;
        esac
    done

    # A timezone that zoneinfo does not have becomes a dangling
    # /etc/localtime at activation, so it is checked here rather than left
    # for the build to discover after the disk is already gone. Re-ask until
    # it resolves; forcing an unknown zone through stays possible for the
    # case this check simply does not know.
    local zdir ans
    if zdir="$(ci_zoneinfo_dir)"; then
        while ! [[ -e "$zdir/${CI_ID[timezone]}" ]]; do
            warning "Timezone '${CI_ID[timezone]}' not found in $zdir."
            read -r -p "  Use it anyway? [y/N]: " ans || return 1
            if [[ "$ans" =~ ^[Yy]([Ee][Ss])?$ ]]; then break; fi
            ci_ask timezone "Timezone" "${CI_ID[timezone]}" || return 1
        done
    else
        warning "No zoneinfo directory found here; the timezone cannot be checked."
    fi

    if ! [[ "${CI_ID[locale]}" =~ ^[A-Za-z][A-Za-z0-9_]*\.[A-Za-z0-9-]+$ ]]; then
        warning "Locale '${CI_ID[locale]}' does not look like en_US.UTF-8; check the spelling."
    fi

    ci_detect_gpu_busids

    local nvidia_default="N" ans=""
    if detect_nvidia; then
        nvidia_default="Y"
        info "NVIDIA GPU detected${CI_GPU_NVIDIA:+ at $CI_GPU_NVIDIA}."
    else
        info "No NVIDIA GPU detected."
    fi

    while true; do
        read -r -p "  Enable NVIDIA support? [$nvidia_default]: " ans || {
            echo
            return 1
        }
        ans="${ans:-$nvidia_default}"
        case "$ans" in
        [Yy] | [Yy][Ee][Ss])
            CI_ID[nvidia]=true
            break
            ;;
        [Nn] | [Nn][Oo])
            CI_ID[nvidia]=false
            break
            ;;
        *)
            warning "Answer y or n."
            ;;
        esac
    done

    if [[ "${CI_ID[nvidia]}" == "true" && -z "$CI_GPU_NVIDIA" ]]; then
        warning "NVIDIA support enabled but no NVIDIA GPU was detected."
        warning "The existing nvidiaBusId/intelBusId in lib/variables.nix will be kept."
    fi

    CI_USER="${CI_ID[username]}"
    CI_EXPECT_HOSTNAME="${CI_ID[hostname]}"
    CI_DEST="$CI_TARGET/home/$CI_USER/$REPO_NAME"
    info "Repository will be installed to ${CI_DEST#"$CI_TARGET"}"
}

# Rewrite the target's variables.nix. Every key is verified to exist BEFORE
# the first edit, because set_var_in dies on a missing key and a die after
# the disk has been repartitioned is the wrong shape of failure.
ci_apply_identity() {
    section "Applying identity"

    local vars="$CI_DEST/lib/variables.nix" k

    if [[ "$CI_DRY_RUN" -eq 1 ]]; then
        for k in "${CI_ID_KEYS[@]}"; do
            run_cmd "$k = \"${CI_ID[$k]}\"  in ${vars#"$CI_TARGET"}"
        done
        run_cmd "nvidia.enable = ${CI_ID[nvidia]}"
        return 0
    fi

    if [[ ! -f "$vars" ]]; then
        error "Missing $vars"
        return 1
    fi

    for k in "${CI_ID_KEYS[@]}"; do
        if ! grep -qE "^[[:space:]]*${k}[[:space:]]*=[[:space:]]*\"" "$vars"; then
            error "Key '$k' not found in lib/variables.nix; refusing a partial edit."
            return 1
        fi
    done

    for k in "${CI_ID_KEYS[@]}"; do
        if ! set_var_in "$vars" "$k" "${CI_ID[$k]}"; then
            error "Could not write '$k' to lib/variables.nix."
            return 1
        fi
    done

    if ! set_nvidia_var "$vars" "${CI_ID[nvidia]}"; then
        error "Could not write nvidia.enable to lib/variables.nix."
        return 1
    fi

    if [[ "${CI_ID[nvidia]}" == "true" ]]; then
        if [[ -n "$CI_GPU_NVIDIA" ]]; then
            if grep -qE '^[[:space:]]*nvidiaBusId[[:space:]]*=' "$vars"; then
                if ! set_var_in "$vars" nvidiaBusId "$CI_GPU_NVIDIA"; then
                    error "Could not write nvidiaBusId."
                    return 1
                fi
                v_ok "nvidiaBusId = $CI_GPU_NVIDIA"
            fi
        else
            v_info "no NVIDIA bus id detected; existing nvidiaBusId kept"
        fi

        if [[ -n "$CI_GPU_INTEL" ]]; then
            if grep -qE '^[[:space:]]*intelBusId[[:space:]]*=' "$vars"; then
                if ! set_var_in "$vars" intelBusId "$CI_GPU_INTEL"; then
                    error "Could not write intelBusId."
                    return 1
                fi
                v_ok "intelBusId = $CI_GPU_INTEL"
            fi
        else
            v_info "no Intel iGPU detected; existing intelBusId kept (needed for PRIME offload)"
        fi
    fi

    success "Identity written to ${vars#"$CI_TARGET"}"
}

# On legacy BIOS the repository's UEFI-only GRUB settings are invalid:
# nixpkgs asserts efiInstallAsRemovable implies efiSupport, and device =
# "nodev" gives grub-install nowhere to write a boot sector. All three keys
# are forced here rather than changed in modules/boot, so the same
# configuration remains correct on the UEFI machine it came from.
ci_apply_bios_override() {
    local f="$1" last tmp

    last="$(tail -n1 "$f" | tr -d '[:space:]' || true)"
    if [[ "$last" != "}" ]]; then
        error "Unexpected end of ${f#"$CI_TARGET"}; cannot append the BIOS bootloader override."
        return 1
    fi

    tmp="$(mktemp)" || return 1
    head -n -1 "$f" >"$tmp"
    cat >>"$tmp" <<OVR

  # setup.sh: legacy BIOS boot. The repository defaults to a UEFI-only GRUB
  # (device = "nodev", efiSupport = true, efiInstallAsRemovable = true), which
  # nixpkgs rejects for BIOS: efiInstallAsRemovable requires efiSupport, and
  # GRUB needs a real disk to write its MBR into. Forced here instead of in
  # modules/boot so the same configuration stays valid under UEFI.
  boot.loader.grub.device = lib.mkForce "${CI_DISK}";
  boot.loader.grub.efiSupport = lib.mkForce false;
  boot.loader.grub.efiInstallAsRemovable = lib.mkForce false;
}
OVR
    mv "$tmp" "$f"
    info "Appended the BIOS GRUB override for $CI_DISK."
    return 0
}

ci_generate_hardware() {
    ci_need_cmd nixos-generate-config
    section "Hardware configuration for the target"

    local dest="$CI_DEST/$HOST_DIR/hardware-configuration.nix"

    if [[ "$CI_DRY_RUN" -eq 1 ]]; then
        run_cmd "nixos-generate-config --root $CI_TARGET --show-hardware-config > ${dest#"$CI_TARGET"}"
        info "The --root flag is what makes this describe the target rather than the ISO."
        if [[ "$CI_FIRMWARE" == "BIOS" ]]; then
            run_cmd "append mkForce grub override (device=$CI_DISK, efiSupport=false) for BIOS"
        fi
        return 0
    fi

    if [[ ! -d "$CI_DEST/$HOST_DIR" ]]; then
        error "No $HOST_DIR at $CI_DEST"
        return 1
    fi

    if ! write_hardware_config "$CI_TARGET" "$dest"; then
        error "Hardware generation failed."
        return 1
    fi

    if [[ "$CI_FIRMWARE" == "BIOS" ]]; then
        if ! ci_apply_bios_override "$dest"; then
            return 1
        fi
        # Read it back rather than trusting the append: without this line
        # the installed system would keep device = "nodev" and GRUB would
        # have nowhere to write -- discovered only after the reboot.
        if ! grep -q 'boot.loader.grub.device = lib.mkForce' "$dest"; then
            error "The BIOS GRUB override is missing from the generated hardware configuration."
            return 1
        fi
    fi

    # Parse-check immediately: a syntactically broken hardware configuration
    # is much cheaper to catch here than inside nixos-install.
    if ! nix-instantiate --parse "$dest" >/dev/null 2>&1; then
        nix-instantiate --parse "$dest" || true
        error "Generated hardware-configuration.nix does not parse."
        return 1
    fi

    # A flake built from a git tree ignores untracked files. Staging this
    # guarantees the build sees the freshly generated file rather than
    # whatever UUIDs happen to be committed. If staging cannot work, the
    # only correct fallback is to stop being a git tree at all: dropping
    # .git makes every file on disk visible, whatever the index says.
    if [[ -d "$CI_DEST/.git" ]]; then
        if command -v git >/dev/null 2>&1 &&
            git -C "$CI_DEST" -c safe.directory='*' add -A >/dev/null 2>&1; then
            info "Staged the generated hardware configuration for the flake."
        else
            warning "Could not stage the new hardware configuration for git."
            warning "Dropping .git so the flake reads every file as a plain path."
            rm -rf "$CI_DEST/.git"
        fi
    fi

    success "Generated against $CI_TARGET."
}

# Round-trip check on lib/variables.nix after the edits: parse it, then read
# every value back and compare with what the questionnaire collected. This
# catches a sed that silently matched nothing.
ci_check_variables() {
    local saved="$V_FAILED" rc=0
    V_FAILED=0
    section "variables.nix"

    if [[ "$CI_DRY_RUN" -eq 1 ]]; then
        v_info "skipped in dry run (edits were shown above)"
        V_FAILED="$saved"
        return 0
    fi

    local vars="$CI_DEST/lib/variables.nix" k got want
    if [[ ! -f "$vars" ]]; then
        v_fail "missing ${vars#"$CI_TARGET"}"
        V_FAILED=1
        return 1
    fi

    if ! nix-instantiate --parse "$vars" >/dev/null 2>&1; then
        nix-instantiate --parse "$vars" || true
        v_fail "lib/variables.nix does not parse"
    else
        v_ok "lib/variables.nix parses"
    fi

    for k in "${CI_ID_KEYS[@]}"; do
        want="${CI_ID[$k]}"
        got="$(sed -nE "s/^[[:space:]]*${k}[[:space:]]*=[[:space:]]*\"([^\"]*)\";.*/\1/p" "$vars" | head -n1 || true)"
        if [[ "$got" == "$want" ]]; then
            v_ok "$k = $got"
        else
            v_fail "$k: wanted '$want', file holds '${got:-<nothing>}'"
        fi
    done

    local nv
    nv="$(get_nvidia_var "$vars" || true)"
    if [[ "$nv" == "${CI_ID[nvidia]}" ]]; then
        v_ok "nvidia.enable = $nv"
    else
        v_fail "nvidia.enable: wanted ${CI_ID[nvidia]}, file holds '${nv:-<nothing>}'"
    fi

    [[ "$V_FAILED" -eq 0 ]] || rc=1
    if [[ "$rc" -ne 0 || "$saved" -ne 0 ]]; then V_FAILED=1; else V_FAILED=0; fi
    return "$rc"
}

# Extract one filesystem block from a generated hardware configuration.
ci_fs_block() {
    awk -v key="fileSystems.\"$2\"" '
    index($0, key) { inblk = 1 }
    inblk         { print }
    inblk && /\};/ { inblk = 0 }
  ' "$1"
}

# UUID of a block device. `-p` probes the device itself rather than the
# blkid cache, which can still hold the pre-format answer from before mkfs
# ran; the plain cache lookup stays as a fallback for whatever libblkid
# cannot probe directly. Run as root either way.
ci_blkid_uuid() {
    local u
    u="$(blkid -p -o value -s UUID "$1" 2>/dev/null || true)"
    if [[ -z "$u" ]]; then
        u="$(blkid -s UUID -o value "$1" 2>/dev/null || true)"
    fi
    printf '%s' "$u"
}

ci_fs_uuid() {
    ci_fs_block "$1" "$2" | sed -nE 's|.*by-uuid/([^"]+)".*|\1|p' | head -n1
}

ci_fs_type() {
    ci_fs_block "$1" "$2" | sed -nE 's|.*fsType[[:space:]]*=[[:space:]]*"([^"]+)".*|\1|p' | head -n1
}

# The generated file must describe THE TARGET, not the previous machine and
# not the ISO. Merges its own results into V_FAILED without discarding
# whatever the caller already recorded.
ci_verify_hardware() {
    local saved="$V_FAILED" rc=0
    V_FAILED=0

    section "Hardware configuration verification"

    local f="$CI_DEST/$HOST_DIR/hardware-configuration.nix"
    if [[ ! -f "$f" ]]; then
        v_fail "missing ${f#"$CI_TARGET"}"
        V_FAILED=1
        return 1
    fi
    v_ok "hardware-configuration.nix present"

    local want_root want_boot got_root got_boot
    want_root="$(ci_blkid_uuid "$CI_ROOT_PART")"
    got_root="$(ci_fs_uuid "$f" "/")"

    if [[ -n "$want_root" && "$got_root" == "$want_root" ]]; then
        v_ok "root UUID matches $CI_ROOT_PART  ($want_root)"
    else
        v_fail "root UUID mismatch: config=${got_root:-none} target=${want_root:-unknown}"
    fi

    if [[ "$(ci_fs_type "$f" "/")" == "ext4" ]]; then
        v_ok "root fsType is ext4"
    else
        v_fail "root fsType is not ext4"
    fi

    if [[ "$CI_FIRMWARE" == "UEFI" ]]; then
        want_boot="$(ci_blkid_uuid "$CI_ESP")"
        got_boot="$(ci_fs_uuid "$f" "/boot")"

        if [[ -n "$want_boot" && "$got_boot" == "$want_boot" ]]; then
            v_ok "boot UUID matches $CI_ESP  ($want_boot)"
        else
            v_fail "boot UUID mismatch: config=${got_boot:-none} target=${want_boot:-unknown}"
        fi

        if [[ "$(ci_fs_type "$f" "/boot")" == "vfat" ]]; then
            v_ok "boot fsType is vfat"
        else
            v_fail "boot fsType is not vfat"
        fi
    else
        if grep -q 'fileSystems."/boot"' "$f"; then
            v_info "a /boot fileSystems entry exists although this is a BIOS install"
        else
            v_ok "no /boot mount recorded (boot lives on the root filesystem)"
        fi
    fi

    # hostPlatform is emitted by recent generators; its absence is harmless
    # because flake.nix pins system = "x86_64-linux" itself.
    if grep -q 'hostPlatform = lib.mkDefault "x86_64-linux"' "$f"; then
        v_ok "hostPlatform is x86_64-linux"
    else
        v_info "no hostPlatform line; flake.nix sets system itself"
    fi

    if grep -q '"nvme"' "$f"; then
        v_ok "nvme present in initrd modules"
    else
        v_info "nvme absent from initrd modules; expected only on a non-NVMe target"
    fi

    if [[ "$V_FAILED" -eq 0 ]]; then rc=0; else rc=1; fi

    if [[ "$rc" -ne 0 || "$saved" -ne 0 ]]; then V_FAILED=1; else V_FAILED=0; fi
    return "$rc"
}

ci_validate_flake() {
    ci_need_cmd nix
    section "Flake validation"

    if [[ "$CI_DRY_RUN" -eq 1 ]]; then
        run_cmd "nix flake check --no-build $CI_DEST"
        return 0
    fi

    local cache="$CI_TARGET/.nix-cache"
    mkdir -p "$cache"
    chmod 700 "$cache"

    info "Using target-disk cache: $cache"
    info "Scratch space: $TMPDIR"

    if ! XDG_CACHE_HOME="$cache" \
        nix "${CI_NIX_FLAGS[@]}" flake check --no-build "$CI_DEST"; then
        error "Flake check failed."
        info "The generated configuration does not evaluate; the install stops here,"
        info "before nixos-install, with the target still mounted for inspection."
        return 1
    fi

    success "Flake evaluates."
}

ci_prepare_target_store() {
    section "Target Nix store"

    local store="$CI_TARGET/nix/store"

    if [[ "$CI_DRY_RUN" -eq 1 ]]; then
        run_cmd "mkdir -p $CI_TARGET/nix/store $CI_TARGET/nix/var/nix"
        run_cmd "nix --store $CI_TARGET store info"
        info "The system build will use the disk-backed target store."
        return 0
    fi

    mkdir -p "$store" "$CI_TARGET/nix/var/nix"
    chmod 755 "$CI_TARGET/nix" "$store" "$CI_TARGET/nix/var/nix"

    if ! nix "${CI_NIX_FLAGS[@]}" --store "$CI_TARGET" store info >/dev/null; then
        error "Target Nix store is not usable: $CI_TARGET"
        return 1
    fi

    success "Target Nix store ready at $store."
}

# Build the system closure straight into the target store, before
# nixos-install runs. Building to a path OUTSIDE the target would make
# nixos-install copy the whole closure over at the end; this way the bytes
# are already on the disk the machine will boot from, RAM is released as the
# build finishes, and a configuration error surfaces here rather than inside
# nixos-install's wrapped output.
ci_build_system() {
    section "Build the system in the target store"

    local attr="$CI_DEST#nixosConfigurations.$FLAKE_HOST.config.system.build.toplevel"

    if [[ "$CI_DRY_RUN" -eq 1 ]]; then
        run_cmd "nix --store $CI_TARGET build --no-link --print-out-paths ${attr}"
        info "The system build will use the disk-backed target store."
        return 0
    fi

    local cache="$CI_TARGET/.nix-cache" result
    mkdir -p "$cache"

    info "Source: $attr"

    if ! result="$(
        XDG_CACHE_HOME="$cache" \
            nix "${CI_NIX_FLAGS[@]}" \
            --store "$CI_TARGET" \
            build \
            --no-link \
            --print-out-paths \
            "$attr"
    )"; then
        error "System build failed."
        info "nix printed the evaluation or build error above."
        info "The target stays mounted at $CI_TARGET for inspection."
        return 1
    fi

    result="$(printf '%s\n' "$result" | tail -n1)"

    if [[ "$result" != /nix/store/* ]]; then
        error "Build returned an unexpected store path: $result"
        return 1
    fi

    if [[ ! -e "$CI_TARGET$result" ]]; then
        error "Built system path does not exist: $result"
        return 1
    fi

    CI_SYSTEM_PATH="$result"

    success "System closure built in the target store."
    info "System path: $result"
}

ci_install() {
    ci_need_cmd nixos-install
    section "Installing NixOS"

    if [[ "$CI_DRY_RUN" -eq 1 ]]; then
        run_cmd "nixos-install --root $CI_TARGET --flake $CI_DEST#$FLAKE_HOST --no-channel-copy --no-root-passwd"
        info "Installs from the flake by name; the closure is already in the target store."
        return 0
    fi

    if [[ -z "$CI_SYSTEM_PATH" ]]; then
        error "No target-store system closure was built."
        return 1
    fi

    # Belt and braces: the build above proved the closure exists in the
    # target store; path-info proves it is still there right before install.
    if ! nix "${CI_NIX_FLAGS[@]}" --store "$CI_TARGET" path-info "$CI_SYSTEM_PATH" >/dev/null; then
        error "System closure vanished from the target store: $CI_SYSTEM_PATH"
        return 1
    fi

    info "Installing flake $CI_DEST#$FLAKE_HOST"
    info "Closure: $CI_SYSTEM_PATH (already in the target store, the rebuild is a no-op)"

    if ! nixos-install \
        --root "$CI_TARGET" \
        --flake "$CI_DEST#$FLAKE_HOST" \
        --no-channel-copy \
        --no-root-passwd; then
        error "nixos-install failed."
        return 1
    fi

    if [[ ! -f "$CI_TARGET/etc/NIXOS" ]]; then
        error "nixos-install reported success but $CI_TARGET/etc/NIXOS is missing."
        return 1
    fi

    success "NixOS installed from $CI_DEST#$FLAKE_HOST."
}

ci_cleanup_installer_artifacts() {
    section "Installer cleanup"

    if [[ "$CI_DRY_RUN" -eq 1 ]]; then
        run_cmd "rm -rf $CI_TARGET/.nix-cache $CI_TARGET/.setup-tmp $CI_TARGET/.nix-tmp"
        run_cmd "rm -f $CI_TARGET/.setup-swapfile $CI_TARGET/.nixos-build-swap"
        info "Installer-only files will be removed from the target."
        return 0
    fi

    if [[ -e "$CI_TARGET/.setup-swapfile" ]]; then
        swapoff "$CI_TARGET/.setup-swapfile" 2>/dev/null || true
    fi
    if [[ -e "$CI_TARGET/.nixos-build-swap" ]]; then
        swapoff "$CI_TARGET/.nixos-build-swap" 2>/dev/null || true
    fi

    rm -rf \
        "$CI_TARGET/.nix-cache" \
        "$CI_TARGET/.setup-tmp" \
        "$CI_TARGET/.nix-tmp" \
        "$CI_TARGET/.nix-root-cache" \
        "$CI_TARGET/backup-usb"

    rm -f \
        "$CI_TARGET/.setup-swapfile" \
        "$CI_TARGET/.nixos-build-swap"

    success "Installer-only files cleaned up."
}

# Give the copied tree back to the user. The uid/gid come from the INSTALLED
# system's own /etc/passwd, parsed directly: nixos-enter would work too, but
# it re-runs activation every time and inherits our PATH, so a plain `id` is
# one more thing that can resolve to the wrong binary.
ci_fix_ownership() {
    section "Ownership"

    if [[ "$CI_DRY_RUN" -eq 1 ]]; then
        run_cmd "chown -R $CI_USER:$CI_USER $CI_TARGET/home/$CI_USER"
        return 0
    fi

    local passwd="$CI_TARGET/etc/passwd" entry uid gid
    if [[ ! -f "$passwd" ]]; then
        error "No $passwd; the target was never activated."
        return 1
    fi

    entry="$(grep -E "^${CI_USER}:" "$passwd" | head -n1 || true)"
    if [[ -z "$entry" ]]; then
        error "User '$CI_USER' is missing from the installed system's /etc/passwd."
        return 1
    fi

    IFS=: read -r _ _ uid gid _ <<<"$entry"
    if [[ ! "$uid" =~ ^[0-9]+$ || ! "$gid" =~ ^[0-9]+$ ]]; then
        error "Could not parse uid/gid for $CI_USER from /etc/passwd."
        return 1
    fi
    CI_USER_UID="$uid"
    CI_USER_GID="$gid"

    if ! ci_run chown -R "$uid:$gid" "$CI_TARGET/home/$CI_USER"; then
        error "chown failed on $CI_TARGET/home/$CI_USER"
        return 1
    fi

    success "$CI_DEST owned by $CI_USER ($uid:$gid)."
}

# Passwords are set through passwd INSIDE the installed system, interactively.
# Root is optional (the ISO's own install asks and skips on failure; here a
# refusal is a legitimate choice), the login user is required: this
# configuration defines no initialPassword and no display manager, so without
# one nobody can get in. Absolute paths inside the chroot, the same form
# nixos-install itself uses.
ci_set_passwords() {
    section "Passwords"
    info "Set interactively inside the installed system."
    info "Never written to Nix, to variables.nix, or to any log."

    if [[ "$CI_DRY_RUN" -eq 1 ]]; then
        run_cmd "nixos-enter --root $CI_TARGET -- passwd root   (optional)"
        run_cmd "nixos-enter --root $CI_TARGET -- passwd $CI_USER"
        return 0
    fi

    CI_PW_ATTEMPTED=1

    local ans="" i
    read -r -p "  Set a root password now? [Y/n]: " ans || ans=""
    if [[ "$ans" =~ ^[Nn] ]]; then
        warning "Root console login will be unavailable."
        v_info "root password skipped (your choice)"
    else
        if nixos-enter --root "$CI_TARGET" -c 'exec /nix/var/nix/profiles/system/sw/bin/passwd root'; then
            v_ok "root password set"
        else
            v_info "root password not set; set later with: nixos-enter --root $CI_TARGET"
        fi
    fi

    for i in 1 2 3; do
        info "Set the password for $CI_USER (attempt $i of 3)."
        if nixos-enter --root "$CI_TARGET" -c "exec /nix/var/nix/profiles/system/sw/bin/passwd $CI_USER"; then
            CI_PW_USER_OK=1
            break
        fi
        warning "passwd failed."
    done

    if [[ "$CI_PW_USER_OK" -eq 1 ]]; then
        v_ok "password set for $CI_USER"
    else
        v_fail "no password set for $CI_USER"
        warning "This configuration defines no initialPassword and no display manager,"
        warning "so $CI_USER cannot log in until a password exists."
        warning "Before rebooting, run:"
        info "  nixos-enter --root $CI_TARGET -- /nix/var/nix/profiles/system/sw/bin/passwd $CI_USER"
    fi
}

ci_verify_bootloader() {
    local saved="$V_FAILED" rc=0
    V_FAILED=0

    section "Bootloader ($CI_FIRMWARE)"

    if [[ "$CI_FIRMWARE" == "UEFI" ]]; then
        local fb="$CI_TARGET/boot/EFI/BOOT/BOOTX64.EFI"

        if [[ -f "$fb" ]]; then
            v_ok "fallback loader present at /boot/EFI/BOOT/BOOTX64.EFI"
        else
            # v_fail sets V_FAILED, which keeps any earlier failure too
            # (V_FAILED is only ever 0 -> 1, never reset mid-function).
            v_fail "missing $fb"
            return 1
        fi

        if grep -qa "systemd-boot" "$fb"; then
            v_fail "fallback loader is systemd-boot, not GRUB"
        elif grep -qa "GRUB" "$fb"; then
            v_ok "fallback loader identifies as GRUB"
        else
            v_info "cannot read an identity from the fallback loader; grub.cfg below is authoritative"
        fi
    else
        local core="$CI_TARGET/boot/grub/i386-pc/core.img"
        if [[ -f "$core" ]]; then
            v_ok "GRUB i386-pc core image present (MBR boot path)"
        else
            v_fail "missing $core; GRUB was not installed for BIOS"
        fi
    fi

    local cfg="$CI_TARGET/boot/grub/grub.cfg"
    if [[ -f "$cfg" ]]; then
        v_ok "grub.cfg present"
    else
        v_fail "missing $cfg"
        return 1
    fi

    if grep -q "menuentry" "$cfg"; then
        v_ok "grub.cfg has menu entries"
    else
        v_fail "grub.cfg has no menuentry"
    fi

    if grep -q "nixos-system" "$cfg"; then
        v_ok "grub.cfg boots a NixOS system closure"
    else
        v_fail "grub.cfg references no NixOS system closure"
    fi

    local sys
    sys="$(readlink -f "$CI_TARGET/nix/var/nix/profiles/system" 2>/dev/null || printf '')"
    if [[ -n "$sys" ]] && grep -q -- "${sys##*/}" "$cfg"; then
        v_ok "grub.cfg references the installed generation"
    else
        v_info "grub.cfg does not name the current system profile; check the menu on first boot"
    fi

    if [[ "$CI_FIRMWARE" == "UEFI" && -d "$CI_TARGET/boot/EFI/systemd" ]]; then
        v_info "$CI_TARGET/boot/EFI/systemd still exists on the new ESP"
    fi

    if [[ "$V_FAILED" -eq 0 ]]; then rc=0; else rc=1; fi
    if [[ "$rc" -ne 0 || "$saved" -ne 0 ]]; then V_FAILED=1; else V_FAILED=0; fi
    return "$rc"
}

ci_efi_entries() { efibootmgr -v 2>/dev/null || true; }

# Read efibootmgr -v on stdin, print NUM|LABEL for entries that are stale
# NixOS systemd-boot loaders and nothing else.
#
# Deliberately narrow. Only an entry naming systemd-bootx64.efi, or carrying
# the label systemd itself writes, is ever a candidate. Anything belonging to
# another operating system is skipped before matching, so a Windows or distro
# entry cannot be selected even if its path happened to mention systemd.
ci_parse_stale_efi() {
    local line num label
    while IFS= read -r line; do
        [[ "$line" =~ ^Boot([0-9A-Fa-f]{4})\*?[[:space:]]+(.*)$ ]] || continue
        num="${BASH_REMATCH[1]}"
        label="${BASH_REMATCH[2]}"

        case "$label" in
        *Microsoft* | *microsoft* | *Windows* | *windows* | *bootmgfw* | \
            *Ubuntu* | *ubuntu* | *Fedora* | *fedora* | *Debian* | *debian* | \
            *grubx64* | *shimx64* | *opensuse* | *Arch*)
            continue
            ;;
        esac

        if printf '%s' "$label" | grep -qiE 'systemd-bootx64\.efi|Linux Boot Manager'; then
            printf '%s|%s\n' "$num" "$label"
        fi
    done
}

ci_handle_stale_efi() {
    section "UEFI boot entries"

    if [[ ! -d /sys/firmware/efi ]]; then
        v_fail "not booted in UEFI mode; this configuration is UEFI only"
        return 1
    fi

    if ! command -v efibootmgr >/dev/null 2>&1; then
        v_fail "efibootmgr unavailable, cannot inspect UEFI boot entries"
        warning "GRUB here is installed only to the removable fallback path and creates"
        warning "no NVRAM entry, so a leftover entry can still win the boot."
        warning "From any live environment run: efibootmgr -v"
        warning "Then delete stale NixOS entries with: efibootmgr -b <NUM> -B"
        return 1
    fi

    local out
    out="$(ci_efi_entries)"
    printf '%s\n' "$out" | sed 's/^/    /'
    echo

    local -a stale=()
    local line num
    while IFS= read -r line; do
        [[ -n "$line" ]] && stale+=("$line")
    done < <(printf '%s\n' "$out" | ci_parse_stale_efi)

    if [[ "${#stale[@]}" -eq 0 ]]; then
        v_ok "no stale systemd-boot entry in NVRAM"
        return 0
    fi

    warning "These NVRAM entries point at the old systemd-boot loader:"
    for line in "${stale[@]}"; do
        printf '    Boot%s  %s\n' "${line%%|*}" "${line#*|}"
    done
    echo
    info "This repository installs GRUB with efiInstallAsRemovable = true and"
    info "efi.canTouchEfiVariables = false, so GRUB lives only at"
    info "\\EFI\\BOOT\\BOOTX64.EFI and registers no NVRAM entry of its own."
    info "While an entry above exists and is ordered ahead of the fallback, the"
    info "firmware will keep booting the previous installation."
    echo

    if [[ "$CI_DRY_RUN" -eq 1 ]]; then
        run_cmd "efibootmgr -b <NUM> -B   for each entry above"
        return 0
    fi

    if ! confirm "Delete the entries listed above?"; then
        v_fail "stale systemd-boot entry left in place; this machine may boot the old system"
        return 1
    fi

    for line in "${stale[@]}"; do
        num="${line%%|*}"
        ci_run efibootmgr -b "$num" -B || warning "Could not delete Boot$num"
    done

    out="$(ci_efi_entries)"
    if printf '%s' "$out" | ci_parse_stale_efi | grep -q .; then
        v_fail "a systemd-boot entry survived deletion"
        return 1
    fi

    success "Stale entries removed."
    printf '%s\n' "$out" | sed 's/^/    /'
}

# Everything a wrong install would get wrong, checked against the target.
# None of these may abort the aggregate: each records into V_FAILED and the
# verdict prints once at the end, after every group has had its say.
ci_final_verify() {
    V_FAILED=0
    section "Final verification"

    if mountpoint -q "$CI_TARGET"; then
        v_ok "$CI_TARGET mounted"
    else
        v_fail "$CI_TARGET not mounted"
    fi

    if [[ "$CI_FIRMWARE" == "UEFI" ]]; then
        if mountpoint -q "$CI_TARGET/boot"; then
            v_ok "$CI_TARGET/boot mounted"
        else
            v_fail "$CI_TARGET/boot not mounted"
        fi
    else
        v_info "BIOS install: /boot lives on the root filesystem (not a separate mount)"
    fi

    local rootfs
    rootfs="$(findmnt -no FSTYPE "$CI_TARGET" 2>/dev/null || true)"
    if [[ "$rootfs" == "ext4" ]]; then
        v_ok "root filesystem is ext4"
    else
        v_fail "root filesystem is '${rootfs:-unknown}', expected ext4"
    fi

    if [[ -f "$CI_TARGET/etc/NIXOS" ]]; then
        v_ok "marked as a NixOS installation (/etc/NIXOS)"
    else
        v_fail "missing $CI_TARGET/etc/NIXOS; nixos-install never completed"
    fi

    # ci_cleanup_installer_artifacts runs before this verification, so what
    # the installer left behind must be gone by now: a stray swapfile or
    # cache directory would survive into the installed system.
    local artifact left=()
    for artifact in .setup-swapfile .setup-tmp .nix-cache .nix-tmp .nixos-build-swap; do
        if [[ -e "$CI_TARGET/$artifact" ]]; then left+=("$artifact"); fi
    done
    if [[ "${#left[@]}" -eq 0 ]]; then
        v_ok "no installer scratch files left on the target"
    else
        v_fail "installer scratch files still present: ${left[*]}"
    fi

    local got_host
    got_host="$(cat "$CI_TARGET/etc/hostname" 2>/dev/null || true)"
    if [[ -n "$CI_EXPECT_HOSTNAME" ]]; then
        if [[ "$got_host" == "$CI_EXPECT_HOSTNAME" ]]; then
            v_ok "hostname is $got_host"
        else
            v_fail "hostname is '${got_host:-<none>}', expected $CI_EXPECT_HOSTNAME"
        fi
    fi

    if grep -qE "^${CI_USER}:" "$CI_TARGET/etc/passwd" 2>/dev/null; then
        v_ok "user $CI_USER exists in the installed /etc/passwd"
    else
        v_fail "user $CI_USER missing from the installed /etc/passwd"
    fi

    if [[ -d "$CI_TARGET/etc" ]]; then
        v_ok "$CI_TARGET/etc exists"
    else
        v_fail "$CI_TARGET/etc missing"
    fi

    if [[ -d "$CI_TARGET/home/$CI_USER" ]]; then
        v_ok "$CI_TARGET/home/$CI_USER exists"
    else
        v_fail "$CI_TARGET/home/$CI_USER missing"
    fi

    if [[ -f "$CI_DEST/flake.nix" && -d "$CI_DEST/$HOST_DIR" ]]; then
        v_ok "repository present at ${CI_DEST#"$CI_TARGET"}"
    else
        v_fail "repository missing at ${CI_DEST#"$CI_TARGET"}"
    fi

    local owner owner_uid owner_gid
    owner="$(stat -c '%U:%G' "$CI_TARGET/home/$CI_USER" 2>/dev/null || printf '')"
    owner_uid="$(stat -c '%u' "$CI_TARGET/home/$CI_USER" 2>/dev/null || printf '')"
    owner_gid="$(stat -c '%g' "$CI_TARGET/home/$CI_USER" 2>/dev/null || printf '')"
    if [[ -z "$owner" || -z "$owner_uid" ]]; then
        v_fail "cannot read ownership of $CI_TARGET/home/$CI_USER"
    elif [[ -n "$CI_USER_UID" && "$owner_uid" != "$CI_USER_UID" ]]; then
        v_fail "home is owned by uid $owner_uid, expected $CI_USER_UID"
    elif [[ -n "$CI_USER_GID" && "$owner_gid" != "$CI_USER_GID" ]]; then
        v_fail "home is owned by gid $owner_gid, expected $CI_USER_GID"
    elif [[ "$owner" == "root:root" ]]; then
        v_fail "$CI_TARGET/home/$CI_USER is still root:root"
    else
        v_ok "home ownership is $owner"
    fi

    if [[ "$CI_PW_ATTEMPTED" -eq 1 ]]; then
        if [[ "$CI_PW_USER_OK" -eq 1 ]]; then
            v_ok "a password was set for $CI_USER"
        else
            v_fail "no password was set for $CI_USER"
        fi
    else
        v_info "password step not run in this session (verify-boot); cannot check it"
    fi

    ci_verify_hardware || true
    ci_verify_bootloader || true

    if [[ "$CI_FIRMWARE" == "UEFI" ]]; then
        ci_handle_stale_efi || true
    else
        v_info "legacy BIOS boot: no NVRAM entries to inspect"
    fi

    echo
    if [[ "$V_FAILED" -eq 0 ]]; then
        verdict "$GREEN" "$ICON_OK" "Installation verified"
        return 0
    fi

    verdict "$RED" "$ICON_FAIL" "Installation NOT verified"
    error "Do not reboot expecting the new configuration until the failures above are resolved."
    info "The target stays mounted at $CI_TARGET; re-check any time with ./setup.sh verify-boot"
    return 1
}

# The review screen: everything the questionnaire decided, everything the
# pipeline will do, printed once before the typed confirmations.
ci_review() {
    section "Review"

    printf '  Firmware  : %s\n' "$CI_FIRMWARE"
    printf '  Disk      : %s  %s\n' "$CI_DISK" "$(ci_disk_desc "$CI_DISK")"
    if [[ "$CI_FIRMWARE" == "UEFI" ]]; then
        printf '  Partitions: %-14s 1GiB fat32 label=%-5s -> %s/boot\n' \
            "$CI_ESP" "$CI_ESP_LABEL" "$CI_TARGET"
        printf '            : %-14s rest ext4  label=%-5s -> %s\n' \
            "$CI_ROOT_PART" "$CI_ROOT_LABEL" "$CI_TARGET"
        printf '  Bootloader: GRUB, UEFI fallback path \\EFI\\BOOT\\BOOTX64.EFI\n'
    else
        printf '  Partitions: %-14s 2MiB BIOS boot (GRUB core, MBR)\n' "$CI_BIOS_PART"
        printf '            : %-14s rest ext4  label=%-5s -> %s\n' \
            "$CI_ROOT_PART" "$CI_ROOT_LABEL" "$CI_TARGET"
        printf '  Bootloader: GRUB, MBR of %s (mkForce override appended)\n' "$CI_DISK"
    fi
    printf '  Username  : %s\n' "${CI_ID[username]}"
    printf '  Full name : %s\n' "${CI_ID[name]}"
    printf '  Hostname  : %s\n' "${CI_ID[hostname]}"
    printf '  Git       : %s <%s>\n' "${CI_ID[gitUser]}" "${CI_ID[email]}"
    printf '  Timezone  : %s   Locale: %s\n' "${CI_ID[timezone]}" "${CI_ID[locale]}"
    printf '  NVIDIA    : %s\n' "${CI_ID[nvidia]}"
    if [[ "${CI_ID[nvidia]}" == "true" ]]; then
        printf '              intelBusId=%s   nvidiaBusId=%s\n' \
            "${CI_GPU_INTEL:-existing}" "${CI_GPU_NVIDIA:-existing}"
    fi
    printf '  Repository: %s\n' "$CI_DEST"
    printf '  Flake     : %s#%s  (%s)\n' "${CI_DEST#"$CI_TARGET"}" "$FLAKE_HOST" "$HOST_DIR"
    echo
    info "Pipeline: release -> partition -> format -> mount -> swap -> copy repo"
    info "          -> identity -> hardware config -> variables check -> flake check"
    info "          -> build in target store -> nixos-install -> passwords -> verify"
    echo
    info "A real run then asks you to type:  ERASE $CI_DISK"
    info "                                and:  INSTALL SUNFLOWER"
}

# Copy the repository to a scratch directory, apply the identity answers to
# the copy, parse variables.nix and evaluate the flake -- read-only with
# respect to the real tree. Called by the dry run, and by a real run BEFORE
# anything is erased, so an unevaluable configuration is found while it
# still costs nothing. The caller decides what a non-zero return means.
#
# `.git` handling is decided here rather than guessed at copy time:
#
#   * What nix's git fetcher sees comes from the index, not from the disk,
#     so files that exist but were never added (a plain unzip, an rsync, a
#     fresh extraction) are invisible to it. `git add -A` inside the copy
#     first: staged content is what gets fetched, and staged means every
#     file on disk.
#   * If evaluation still fails while .git is present, the copy is checked
#     again WITHOUT it. A plain path fetches every file regardless of git
#     state. When that is what works, CI_STRIP_GIT=1 records that the
#     target copy must be placed the same way, by ci_place_repo.
#
# Returns 1 when the configuration does not evaluate; the scratch copy is
# then left in place so the errors can be inspected.
ci_validate_config_copy() {
    local tmp copy k vars failed=0

    section "Validating the configuration (read-only)"

    tmp="$(mktemp -d)" || {
        warning "No temporary directory; cannot validate."
        return 1
    }
    copy="$tmp/$REPO_NAME"

    info "Copying the repository to ${tmp} for validation."
    if ! cp -a "$ROOT/." "$copy/" 2>/dev/null; then
        warning "Could not copy the repository; cannot validate."
        rm -rf "$tmp"
        return 1
    fi
    rm -rf "$copy/.setup-backups"

    if [[ -d "$copy/.git" ]] && command -v git >/dev/null 2>&1; then
        git config --global --add safe.directory "$copy" 2>/dev/null || true
        git -C "$copy" add -A >/dev/null 2>&1 || true
    fi

    vars="$copy/lib/variables.nix"
    if [[ -f "$vars" ]]; then
        for k in "${CI_ID_KEYS[@]}"; do
            if [[ -z "${CI_ID[$k]-}" ]]; then
                v_info "no answer for '$k' yet; the existing file is left as-is"
                continue
            fi
            if ! grep -qE "^[[:space:]]*${k}[[:space:]]*=[[:space:]]*\"" "$vars"; then
                v_fail "key '$k' not found in lib/variables.nix"
                failed=1
                continue
            fi
            if ! set_var_in "$vars" "$k" "${CI_ID[$k]}"; then
                v_fail "could not write '$k'"
                failed=1
            fi
        done
        if [[ -n "${CI_ID[nvidia]-}" ]]; then
            if ! set_nvidia_var "$vars" "${CI_ID[nvidia]}"; then
                v_fail "could not write nvidia.enable"
                failed=1
            fi
        fi

        if [[ "$failed" -eq 0 ]] && command -v nix-instantiate >/dev/null 2>&1; then
            if nix-instantiate --parse "$vars" >/dev/null 2>&1; then
                v_ok "lib/variables.nix parses with the new identity"
            else
                v_fail "lib/variables.nix does not parse with the new identity"
                failed=1
            fi
        fi
    else
        v_fail "lib/variables.nix missing from the copy"
        failed=1
    fi

    if command -v nix >/dev/null 2>&1 && ci_check_network >/dev/null 2>&1; then
        if nix "${CI_NIX_FLAGS[@]}" flake check --no-build "$copy" >/dev/null 2>&1; then
            v_ok "flake evaluates with the new identity"
            # Proven with .git (when there is one): keep it, subject to the
            # health check ci_place_repo still applies.
            CI_STRIP_GIT=0
        elif [[ -d "$copy/.git" ]]; then
            v_info "flake check failed with .git present; retrying without it"
            rm -rf "$copy/.git"
            if nix "${CI_NIX_FLAGS[@]}" flake check --no-build "$copy" >/dev/null 2>&1; then
                v_ok "flake evaluates as a plain path; the git state was the problem"
                CI_STRIP_GIT=1
            else
                v_fail "flake check failed with and without .git"
                info "Inspect the copy, or re-run showing the errors: nix flake check --no-build $copy"
                failed=1
            fi
        else
            v_fail "flake check failed on the temporary copy"
            info "Inspect the copy, or re-run showing the errors: nix flake check --no-build $copy"
            failed=1
        fi
        # No .git in the copy any more (never had one, or just stripped):
        # the target copy must be placed the same way.
        if [[ ! -d "$copy/.git" ]]; then CI_STRIP_GIT=1; fi
    else
        v_info "flakes/network unavailable here; flake evaluation not tested"
    fi

    if [[ "$failed" -eq 0 ]]; then
        rm -rf "$tmp"
        return 0
    fi
    # Keep the copy: "flake check failed on a directory that no longer
    # exists" is not a useful message.
    v_info "scratch copy kept at $tmp for inspection"
    return 1
}

# Dry run: exercise every read-only part of the pipeline against a temporary
# copy of the repository, on any machine, with no disk effects at all.
ci_dryrun_validate() {
    # Problems are reported by the shared validator; a dry run always ends
    # with the plan summary and a return 0 -- nothing changed either way.
    local failed=0
    ci_validate_config_copy || failed=1

    echo
    section "What a real run would verify"
    info "target mounts and filesystem types, /etc/NIXOS marker"
    info "generated UUIDs against the real target partitions"
    info "variables.nix round-trip (every key read back)"
    info "$CI_FIRMWARE bootloader: $([[ "$CI_FIRMWARE" == "UEFI" ]] && printf 'fallback binary, grub.cfg, stale NVRAM entries' || printf 'i386-pc core image, grub.cfg')"
    info "home ownership is not root:root, a password was set"

    echo
    if [[ "$failed" -eq 0 ]]; then
        verdict "$CYAN" "$ICON_INFO" "Dry run complete, nothing changed"
    else
        verdict "$RED" "$ICON_FAIL" "Dry run found problems, nothing changed"
    fi
    info "Re-run without --dry-run (or choose Fresh install) to perform the installation."
    return 0
}

clean_install() {
    CI_DRY_RUN=0
    case "${1:-}" in
    --dry-run | -n) CI_DRY_RUN=1 ;;
    esac

    ci_firmware_detect

    clear_screen
    panel "Sunflower Clean Installation" "v$VERSION" \
        "Firmware  : $CI_FIRMWARE" \
        "Flake     : #$FLAKE_HOST  ($HOST_DIR)" \
        "Target    : $CI_TARGET, repo at /home/<user>/$REPO_NAME" \
        "Bootloader: GRUB ($([[ "$CI_FIRMWARE" == "UEFI" ]] && printf 'UEFI fallback path' || printf 'MBR of the target disk'))"
    echo

    if [[ "$CI_DRY_RUN" -eq 1 ]]; then
        verdict "$CYAN" "$ICON_INFO" "DRY RUN — NO CHANGES WILL BE MADE"
        echo
    else
        # All three are environment gates, not failures: refusing here is a
        # cancel (return 0), the same shape as every other pre-destructive
        # abort, so the menu keeps running.
        if ! ci_require_tty; then
            warning "Installation cancelled; nothing was changed."
            return 0
        fi
        if ! ci_require_live; then
            warning "Installation cancelled; nothing was changed."
            return 0
        fi
        if ! ci_require_root; then
            warning "Installation cancelled; nothing was changed."
            return 0
        fi
    fi

    # NIX_CONFIG (experimental-features = nix-command flakes) is exported at
    # the top of this file for the whole process tree, so nixos-install and
    # nixos-enter inherit it too. Re-asserted here only as a reminder that
    # every nix call below depends on it.
    : "${NIX_CONFIG:?flakes must be enabled before the installer runs}"

    # --- pre-destructive: every failure here cancels cleanly (return 0) ---
    CI_PHASE="preflight"
    if ! ci_preflight; then
        warning "Installation cancelled; nothing was changed."
        return 0
    fi

    CI_PHASE="identity"
    if ! ci_collect_identity; then
        warning "Installation cancelled; nothing was changed."
        return 0
    fi

    ci_show_disks || true
    CI_PHASE="review"
    if ! ci_select_target_disk; then
        # A dry run is allowed anywhere, including machines with no usable
        # candidate disk: the configuration check still matters.
        if [[ "$CI_DRY_RUN" -eq 1 ]]; then
            warning "No target disk available here; validating the configuration only."
            ci_dryrun_validate
            return 0
        fi
        warning "Disk selection cancelled; nothing was changed."
        return 0
    fi

    ci_review

    if [[ "$CI_DRY_RUN" -eq 1 ]]; then
        ci_dryrun_validate
        return 0
    fi

    # The configuration is proved to evaluate BEFORE anything is erased,
    # not after the disk is already gone. A missing answer, a typo in
    # variables.nix or a flake that only breaks on this machine surfaces
    # here, where it is still free to fix.
    if ! ci_validate_config_copy; then
        warning "Installation cancelled; nothing was changed."
        return 0
    fi

    if ! ci_confirm_destroy; then
        warning "Aborted; nothing was changed."
        return 0
    fi

    # Between the listing and this point the machine kept running: a desktop
    # may have auto-mounted a partition, a USB may have been re-plugged.
    # Re-derive everything from the kernel, then decide again.
    if ! ci_verify_target_disk; then
        warning "Installation cancelled; nothing was changed."
        return 0
    fi

    # --- DESTRUCTIVE PHASE ---------------------------------------------
    # From here on every call is BARE: errexit and the ERR trap must be
    # active inside them. A failure prints its own message, returns 1, and
    # ci_on_error reports the phase and state before exiting.
    CI_STARTED_DESTRUCTIVE=1
    CI_PHASE="destructive"

    ci_release_target
    ci_partition
    ci_format
    ci_mount
    ci_setup_swap

    CI_PHASE="configure"
    ci_place_repo
    ci_apply_identity
    ci_generate_hardware
    ci_check_variables
    ci_verify_hardware
    ci_prepare_target_store
    ci_validate_flake

    CI_PHASE="install"
    ci_check_space
    ci_build_system
    ci_install

    # Nothing after this point needs the extra memory, and a swapfile on a
    # system whose configuration declares no swap would be a surprise.
    ci_teardown_swap

    ci_fix_ownership
    ci_set_passwords

    # Installer droppings come off first: .setup-swapfile and friends must
    # not be counted or verified as part of the finished system.
    ci_cleanup_installer_artifacts

    CI_PHASE="verify"
    ci_final_verify
    CI_PHASE="done"

    echo
    success "Clean installation complete."
    info "The target stays mounted at $CI_TARGET for inspection."
    info "Reboot; GRUB already lists the newest generation as the default."
    echo
    if confirm "Reboot now?"; then
        reboot || warning "Reboot failed; run 'reboot' yourself."
    else
        success "Left mounted. Unmount when ready with: umount -R $CI_TARGET"
    fi
    return 0
}

# Reclaim disk space.
#
# Composed from the maintenance functions rather than reimplementing them, so
# there is one copy of each destructive step and each keeps its own
# confirmation. Deliberately does not run the dry-build gate that the full
# maintenance dashboard imposes: this is the quick "I need space now" path, and
# nothing here touches the configuration.
free_space() {
    clear_screen
    panel "Free disk space" "v$VERSION" \
        "Old generations, garbage collection, store optimisation"
    echo

    info "The configuration is never modified. Only build artefacts and old"
    info "generations are removed, and each step asks first."
    echo

    section "Before"
    m_store_usage

    m_generation_status
    m_cleanup_generations
    m_garbage_collect
    m_optimize_store

    section "After"
    m_store_usage

    echo
    success "Cleanup complete."
}

# Re-run the post-install verification against whatever is mounted at /mnt.
# Shared by the menu and the CLI so there is one copy. Re-derives every input
# the verifier reads from the target itself, so it works standalone -- no
# questionnaire state needed.
verify_boot() {
    if ! mountpoint -q "$CI_TARGET"; then
        error "nothing is mounted at $CI_TARGET"
        info "Mount the installed system first, e.g. mount /dev/<root-part> $CI_TARGET"
        return 1
    fi

    ci_firmware_detect

    # Username: local variables.nix if this checkout has one, else any home
    # directory carrying a repository checkout on the target.
    CI_USER="$(get_var username || printf '')"
    if [[ -z "$CI_USER" ]]; then
        local d
        for d in "$CI_TARGET"/home/*/"$REPO_NAME"; do
            [[ -d "$d" ]] || continue
            CI_USER="$(basename "$(dirname "$d")")"
            break
        done
    fi
    if [[ -z "$CI_USER" ]]; then
        error "cannot determine the installed username under $CI_TARGET/home"
        return 1
    fi

    CI_DEST="$CI_TARGET/home/$CI_USER/$REPO_NAME"
    CI_ROOT_PART="$(findmnt -no SOURCE "$CI_TARGET" 2>/dev/null || printf '')"
    CI_ESP="$(findmnt -no SOURCE "$CI_TARGET/boot" 2>/dev/null || printf '')"

    # Expected hostname from the TARGET's variables file (the local copy may
    # not match what was actually installed). Empty skips the comparison.
    CI_EXPECT_HOSTNAME="$(sed -n 's/^[[:space:]]*hostname[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$CI_DEST/lib/variables.nix" 2>/dev/null | head -n1 || true)"

    # Expected owner from the target's own /etc/passwd: home must match the
    # uid the installed system thinks this user has.
    CI_USER_UID="$(awk -F: -v u="$CI_USER" '$1 == u { print $3 }' \
        "$CI_TARGET/etc/passwd" 2>/dev/null | head -n1 || printf '')"
    CI_USER_GID="$(awk -F: -v u="$CI_USER" '$1 == u { print $4 }' \
        "$CI_TARGET/etc/passwd" 2>/dev/null | head -n1 || printf '')"

    # No password step ran in this session; the verifier reports it as info.
    CI_PW_ATTEMPTED=0
    CI_PW_USER_OK=0

    ci_final_verify
}

usage() {
    cat <<EOF
Sunflower NixOS Installer v$VERSION

Usage:
  ./setup.sh                         Interactive menu (environment-aware)
  ./setup.sh install                 Install this machine (see below)
  ./setup.sh upgrade                 Pull repo + update flake inputs + rebuild
  ./setup.sh free-space              Old generations, GC, store optimisation

  ./setup.sh clean-install           Fresh install (live installer ISO only)
  ./setup.sh clean-install --dry-run Plan a fresh install, change nothing
  ./setup.sh validate                Alias of clean-install --dry-run
  ./setup.sh verify-boot             Re-verify an installation mounted at /mnt
  ./setup.sh configure               Identity pass on an existing install
  ./setup.sh rebuild                 Validate + rebuild/switch
  ./setup.sh dry                     Dry rebuild
  ./setup.sh check                   Flake check
  ./setup.sh maintain                Full maintenance dashboard
  ./setup.sh rollback                Roll back one generation
  ./setup.sh hardware                Regenerate hardware config
  ./setup.sh generations             List system generations
  ./setup.sh gc                      Garbage collection
  ./setup.sh optimize                Optimize Nix store
  ./setup.sh verify-store            Verify Nix store contents
  ./setup.sh systemd                 Check failed systemd units
  ./setup.sh store                   Show Nix store usage
  ./setup.sh test-install            Safe installer preview
  ./setup.sh help                   Show this help
  ./setup.sh version                Show version

What 'install' does depends on where you run it:
  from the installer ISO   the Fresh Install flow: questionnaire, typed
                           confirmations, partition, nixos-install
  on a running NixOS       identity pass, ends in nixos-rebuild switch

Typical life of a machine:
  1. Boot the installer, clone this repo, ./setup.sh, choose 1 (Fresh install).
  2. Reboot into it. Later, ./setup.sh and choose 1 (Upgrade).
  3. When the disk fills up, choose 2 (Free disk space).

Clone once, if this checkout is all you have:
  git clone $REPO_URL && cd $REPO_NAME && ./setup.sh

A plain download or copy works just as well -- .git is never required, for
installing, rebuilding or updating. What git does provide (history, git
pull) is skipped gracefully when it is missing.

Nothing needs installing first. The installer ISO already carries every
tool this uses, and preflight says so before anything is touched.

Password handling:
  Linux passwords are never written to Nix. Setup uses 'passwd' interactively.
EOF
}

main() {
    cd "$ROOT"
    case "${1:-menu}" in
    menu) menu ;;
    # `install` means "install this machine" in whichever environment you are
    # standing in. From the ISO that is a fresh install; on a running NixOS it
    # is the identity/setup pass it has always been, so nobody's habit breaks.
    install)
        if ci_is_live_installer; then ci_install_entry; else install_flow; fi
        ;;
    clean-install | clean_install)
        shift || true
        if [[ $# -gt 1 ]]; then
            error "Unexpected extra arguments: ${*:2}"
            info "Usage: ./setup.sh clean-install [--dry-run]"
            exit 2
        fi
        ci_install_entry "${1:-}"
        ;;
    # The plan, without the installation: same flow, --dry-run.
    validate | plan)
        ci_install_entry --dry-run
        ;;
    configure | identity) install_flow ;;
    verify-boot | verify-install) verify_boot ;;
    upgrade | update) update_config ;;
    free-space | freespace | space) free_space ;;
    rebuild | switch) rebuild ;;
    dry | dry-build) dry_build ;;
    check) flake_check ;;
    maintain | maintenance | cleanup) m_maintenance_dashboard ;;
    rollback) rollback ;;
    hardware | hw) refresh_hardware ;;
    generations | list-generations) list_generations ;;
    gc | garbage-collect) m_garbage_collect ;;
    optimize | optimise) m_optimize_store ;;
    verify-store | verify) m_verify_store ;;
    systemd) m_systemd_health ;;
    store | store-usage) m_store_usage ;;
    test-install) test_install ;;
    help | -h | --help) usage ;;
    version | -v | --version) printf '%s\n' "$VERSION" ;;
    *)
        error "Unknown command: $1"
        usage
        exit 2
        ;;
    esac
}

main "$@"
