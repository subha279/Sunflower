{ pkgs, lib, ... }:

let
  thunarUiDefaults = pkgs.writeShellScript "thunar-ui-defaults" ''
    set -euo pipefail

    if ! command -v xfconf-query >/dev/null 2>&1; then
      exit 0
    fi

    if [[ -z "''${DBUS_SESSION_BUS_ADDRESS:-}" && -S "/run/user/$(id -u)/bus" ]]; then
      export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
    fi

    if [[ -z "''${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
      exit 0
    fi

    set_default() {
      local prop="$1" type="$2" value="$3"

      if xfconf-query --channel thunar --property "$prop" >/dev/null 2>&1; then
        return 0
      fi

      xfconf-query --channel thunar --property "$prop" \
        --create --type "$type" --set "$value" >/dev/null 2>&1 || true
    }

    set_default /misc-use-csd bool true
    set_default /last-menubar-visible bool false
    set_default /last-location-bar string ThunarLocationButtons
    set_default /misc-small-toolbar-icons bool true
    set_default /misc-symbolic-icons-in-sidepane bool true
    set_default /last-toolbar-items string "menu:1,back:1,forward:1,open-parent:1,open-home:1,new-tab:1,new-window:0,toggle-split-view:1,undo:0,redo:0,zoom-out:0,zoom-in:0,zoom-reset:0,view-as-icons:0,view-as-detailed-list:0,view-as-compact-list:0,view-switcher:1,location-bar:1,reload:1,search:1,uca-action-open-terminal-here:1"
  '';
in
{
  home.activation.thunarUiDefaults = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    "${thunarUiDefaults}" || true
  '';

  systemd.user.services.thunar-ui-defaults = {
    Unit = {
      Description = "Apply Sunflower Thunar UI defaults";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${thunarUiDefaults}";
      Slice = "session.slice";
    };

    Install = {
      WantedBy = [ "desktop-services.target" ];
    };
  };
}
