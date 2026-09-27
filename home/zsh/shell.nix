{ config, ... }:

{
  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";

    # Shell Options
    setOptions = [
      "AUTO_CD"
      "AUTO_PUSHD"
      "PUSHD_IGNORE_DUPS"
      "PUSHD_SILENT"
      "EXTENDED_GLOB"
      "NO_BEEP"
      "INTERACTIVE_COMMENTS"
    ];

    # Environment
    envExtra = ''
      # Sunflower → Starship
      export STARSHIP_CONFIG="$HOME/.config/sunflower/active-starship.toml"
    '';

    profileExtra = ''
      # Sunflower → Hyprland session (only on TTY1, not SSH, not already in Wayland)
      if [[ -z "''${WAYLAND_DISPLAY:-}" ]] && [[ -z "''${SSH_CONNECTION:-}" ]] && [[ "''${XDG_VTNR:-0}" == "1" ]] && [[ "$(tty)" == "/dev/tty1" ]]; then
        exec start-hyprland
      fi
    '';

    # Interactive Zsh Configuration
    initContent = ''

      clear() {
        command clear
        printf '\033[3J'
      }

      if [[ -o interactive ]]; then
        typeset -g SUNFLOWER_ZSH_REFRESH_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/sunflower-zsh"
        mkdir -p "$SUNFLOWER_ZSH_REFRESH_DIR"
        typeset -g SUNFLOWER_ZSH_REFRESH_FIFO="$SUNFLOWER_ZSH_REFRESH_DIR/zsh-$$"
        if [[ -e "$SUNFLOWER_ZSH_REFRESH_FIFO" ]]; then
          rm -f "$SUNFLOWER_ZSH_REFRESH_FIFO"
        fi
        mkfifo "$SUNFLOWER_ZSH_REFRESH_FIFO"
        exec {SUNFLOWER_ZSH_REFRESH_FD}<>"$SUNFLOWER_ZSH_REFRESH_FIFO"
        sunflower-zsh-refresh-widget() {
          local fd="$1"
          local message
          read -r -t 0.05 -u "$fd" message 2>/dev/null || true
          zle reset-prompt
          zle -R
          }

        zle -N sunflower-zsh-refresh-widget
        zle -F \
          -w \
          "$SUNFLOWER_ZSH_REFRESH_FD" \
          sunflower-zsh-refresh-widget
        sunflower-zsh-cleanup() {
          zle -F \
            "$SUNFLOWER_ZSH_REFRESH_FD" \
            2>/dev/null || true
          eval "exec ''${SUNFLOWER_ZSH_REFRESH_FD}>&-" \
            2>/dev/null || true
          rm -f \
            "$SUNFLOWER_ZSH_REFRESH_FIFO" \
            2>/dev/null || true
        }
        zshexit_functions+=(
          sunflower-zsh-cleanup
        )

      fi
    '';
  };

  # Starship
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };
}
