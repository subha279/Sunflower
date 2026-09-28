#!/usr/bin/env sh

# Lid switch handler for Hyprland.
#
#   monitor.sh close  -> hide the internal panel (lid closed, external display present)
#   monitor.sh open   -> show the internal panel  (lid open)
#   monitor.sh sync   -> decide from the real lid state (start, reload, hotplug)
#
# Internal panels (eDP*, DSI*, LVDS*, IDP*) and external displays are detected at runtime.

set -eu

# Geometry used when the panel is turned back on.
# Keep in sync with the laptop rule in config/monitor.lua.
PANEL_MODE="preferred"
PANEL_POSITION="auto"
PANEL_SCALE="1"

lid_state() {
    state="$(cat /proc/acpi/button/lid/*/state 2>/dev/null || true)"
    case "$state" in
    *closed*) printf 'closed\n' ;;
    *open*) printf 'open\n' ;;
    *) printf 'unknown\n' ;;
    esac
}

# "name enabled" lines for every known output, disabled ones included.
monitors="$(hyprctl monitors all | awk '/^Monitor /{name = $2} $1 == "disabled:"{print name, $2}')"

if [ -z "$monitors" ]; then
    echo "monitor.sh: hyprctl reported no monitors" >&2
    exit 1
fi

internal=""
external=0

while read -r name disabled; do
    if [ -z "$name" ]; then
        continue
    fi
    case "$name" in
    eDP* | DSI* | LVDS* | IDP*) internal="$internal $name:$disabled" ;;
    *) external=$((external + 1)) ;;
    esac
done <<EOF
$monitors
EOF

action="${1:-sync}"

case "$action" in
close | open) ;;
sync)
    if [ "$(lid_state)" = "closed" ] && [ "$external" -gt 0 ]; then
        action=close
    else
        action=open
    fi
    ;;
*)
    echo "usage: $0 close|open|sync" >&2
    exit 2
    ;;
esac

# Without an external display there is nothing left to look at: never go dark.
if [ "$action" = "close" ] && [ "$external" -eq 0 ]; then
    exit 0
fi

if [ "$action" = "close" ]; then
    target=true
else
    target=false
fi

for entry in $internal; do
    name="${entry%%:*}"
    state="${entry##*:}"

    # Only touch panels that are not already in the desired state.
    if [ "$state" = "$target" ]; then
        continue
    fi

    if [ "$target" = "true" ]; then
        rule="{ output = \"$name\", disabled = true }"
    else
        rule="{ output = \"$name\", mode = \"$PANEL_MODE\", position = \"$PANEL_POSITION\", scale = $PANEL_SCALE, disabled = false }"
    fi

    if ! out="$(hyprctl eval "hl.monitor($rule)" 2>&1)"; then
        printf 'monitor.sh: %s\n' "$out" >&2
        exit 1
    fi
done
