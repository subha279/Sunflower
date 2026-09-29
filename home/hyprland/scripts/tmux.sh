#!/usr/bin/env bash

set -euo pipefail

# Sunflower Tmux Sessionizer
# Configuration
SEARCH_DIRS=(
    "$HOME/Sunflower"
    "$HOME/Projects"
)

# Nerd Font icons
ICON_SESSION=" "
ICON_DIR=" "
ICON_POINTER="❖"

# Spinner
UI_SPIN=("◜" "◠" "◝" "◞" "◡" "◟")

# Animation
SPIN_DELAY=0.08
MIN_LOADING_TIME=0.70

# Directories never crawled
PRUNE_PATHS=(
    '*/.git'
    '*/.cache'
    '*/node_modules'
    '*/.local/share'
)

# Temporary directory
TMP_DIR=""

# UI
hide_cursor() {
    printf '\033[?25l'
}

show_cursor() {
    printf '\033[?25h'
}

clear_line() {
    printf '\r\033[K'
}

cleanup() {
    show_cursor
    clear_line
    if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
    fi
}

trap cleanup EXIT
trap 'exit 130' INT TERM

# Spinner
spinner() {
    local message="$1"
    local pid="$2"
    local i=0
    local started
    local now
    local elapsed
    started=$(date +%s%N)
    hide_cursor

    # Animate while the scanner is running
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r\033[K  %s  %s' \
            "${UI_SPIN[$i]}" \
            "$message"
        i=$(((i + 1) % ${#UI_SPIN[@]}))
        sleep "$SPIN_DELAY"
    done

    # Keep spinner visible for at least MIN_LOADING_TIME
    while true; do
        now=$(date +%s%N)
        elapsed=$((now - started))
        # 700ms = 700000000ns
        if ((elapsed >= 700000000)); then
            break
        fi
        printf '\r\033[K  %s  %s' \
            "${UI_SPIN[$i]}" \
            "$message"
        i=$(((i + 1) % ${#UI_SPIN[@]}))
        sleep "$SPIN_DELAY"
    done
    clear_line
    show_cursor
}

# tmux
enter_session() {
    local session="$1"

    if [[ -n "${TMUX:-}" ]]; then
        tmux switch-client -t "=$session"
    else
        tmux attach-session -t "=$session"
    fi
}

# Directory Discovery
find_directories() {
    local dir

    for dir in "${SEARCH_DIRS[@]}"; do

        [[ -d "$dir" ]] || continue

        find "$dir" \
            \( \
            -path '*/.git' \
            -o -path '*/.cache' \
            -o -path '*/node_modules' \
            -o -path '*/.local/share' \
            \) \
            -prune \
            -o \
            -type d \
            -print \
            2>/dev/null

    done
}

# Session Name
make_session_name() {
    local directory="$1"
    local name

    name="$(basename "$directory")"

    # Lowercase
    name="${name,,}"

    # Replace invalid characters with _
    name="$(
        printf '%s' "$name" |
            sed 's/[^a-z0-9-]/_/g'
    )"

    # Collapse repeated underscores
    name="$(
        printf '%s' "$name" |
            sed 's/_\{2,\}/_/g'
    )"

    # Remove leading/trailing underscores
    name="${name##_}"
    name="${name%_}"

    # Fallback
    if [[ -z "$name" ]]; then
        name="session"
    fi
    printf '%s' "$name"
}

# Main
main() {
    # Temporary files
    TMP_DIR="$(mktemp -d)"
    local sessions_file="$TMP_DIR/sessions"
    local directories_file="$TMP_DIR/directories"
    local entries_file="$TMP_DIR/entries"

    # Existing tmux sessions
    tmux list-sessions \
        -F '#{session_name}' \
        2>/dev/null \
        >"$sessions_file" || true

    # Scan directories
    find_directories >"$directories_file" &
    local scanner_pid=$!
    spinner "Scanning projects..." "$scanner_pid"

    # Make sure scanner is completely finished
    wait "$scanner_pid" || true
    # Build fzf list
    {
        # Existing sessions
        if [[ -s "$sessions_file" ]]; then
            while IFS= read -r session; do
                printf '%s%s\n' \
                    "$ICON_SESSION" \
                    "$session"
            done <"$sessions_file"
        fi

        # Project directories
        if [[ -s "$directories_file" ]]; then
            while IFS= read -r directory; do
                printf '%s%s\n' \
                    "$ICON_DIR" \
                    "$directory"
            done <"$directories_file"
        fi

    } | sort -u >"$entries_file"

    # Nothing found
    if [[ ! -s "$entries_file" ]]; then
        exit 0
    fi

    # fzf
    local selected=""
    selected="$(
        fzf \
            --height='60%' \
            --layout=reverse \
            --border \
            --prompt='Project  ' \
            --pointer="$ICON_POINTER" \
            --border-label=" ${ICON_DIR} Tmux Session" \
            --color='bg:-1,bg+:-1,gutter:-1' \
            <"$entries_file"
    )" || true

    # Cancelled
    if [[ -z "$selected" ]]; then
        exit 0
    fi

    # Existing tmux session
    if [[ "$selected" == "$ICON_SESSION"* ]]; then
        local session="${selected#"$ICON_SESSION"}"
        enter_session "$session"
        exit 0
    fi

    # Directory
    if [[ "$selected" == "$ICON_DIR"* ]]; then

        local path="${selected#"$ICON_DIR"}"
        local directory

        directory="$(realpath "$path")"

        # Generate session name
        local session
        session="$(make_session_name "$directory")"

        # Create session if necessary
        if ! tmux has-session -t "=$session" 2>/dev/null; then

            tmux new-session \
                -d \
                -s "$session" \
                -c "$directory"

        fi
        enter_session "$session"
    fi
}

main "$@"
