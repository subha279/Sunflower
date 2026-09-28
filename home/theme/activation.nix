{ lib, ... }:

let
  themeData = import ../../lib/themes.nix;
  defaultTheme = themeData.global.activeTheme;
in
{
  home.activation.initializeSunflowerTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    theme_dir="$HOME/.config/sunflower"
    theme_file="$theme_dir/active-theme"
    active_lua="$theme_dir/active-theme.lua"
    active_kitty="$theme_dir/active-kitty.conf"
    active_tmux="$theme_dir/active-tmux.conf"
    active_starship="$theme_dir/active-starship.toml"
    default_theme="${defaultTheme}"

    mkdir -p "$theme_dir"
    mkdir -p "$HOME/.cache/sunflower"

    if [ ! -f "$theme_file" ]; then
      printf '%s\n' "$default_theme" > "$theme_file"
    fi

    selected="$(cat "$theme_file")"

    # A theme id is a bare filename fragment. Anything else (empty, whitespace,
    # a path, or an id no generator produced) falls back to the default rather
    # than being spliced straight into a symlink target.
    case "$selected" in
      ""|*/*|*..*)
        selected="$default_theme"
        ;;
    esac

    if [[ ! -f "$theme_dir/themes/$selected.lua" ]]; then
      selected="$default_theme"
    fi

    if [ "$(cat "$theme_file")" != "$selected" ]; then
      printf '%s\n' "$selected" > "$theme_file"
    fi

    if [[ -f "$theme_dir/themes/$selected.kitty.conf" ]]; then
      ln -sfn "$theme_dir/themes/$selected.kitty.conf" "$active_kitty"
    else
      ln -sfn "$theme_dir/themes/$default_theme.kitty.conf" "$active_kitty"
    fi

    if [[ -f "$theme_dir/themes/$selected.tmux.conf" ]]; then
      ln -sfn "$theme_dir/themes/$selected.tmux.conf" "$active_tmux"
    else
      ln -sfn "$theme_dir/themes/$default_theme.tmux.conf" "$active_tmux"
    fi

    if [[ -f "$theme_dir/themes/$selected.starship.toml" ]]; then
      ln -sfn "$theme_dir/themes/$selected.starship.toml" "$active_starship"
    else
      ln -sfn "$theme_dir/themes/$default_theme.starship.toml" "$active_starship"
    fi

    ln -sfn "$theme_dir/themes/$selected.lua" "$active_lua"

    gtk3_dir="$HOME/.config/gtk-3.0"
    gtk4_dir="$HOME/.config/gtk-4.0"
    kvantum_dir="$HOME/.config/Kvantum"
    kvantum_theme="$kvantum_dir/Base16Kvantum"

    mkdir -p "$gtk3_dir" "$gtk4_dir" "$kvantum_dir"

    # Only wire up assets that were actually generated for this theme, so a
    # half-generated theme can never leave GTK/Kvantum pointing nowhere.
    if [[ -f "$theme_dir/themes/$selected/gtk-3.0/gtk.css" ]]; then
      ln -sfn "$theme_dir/themes/$selected/gtk-3.0/gtk.css" "$gtk3_dir/gtk.css"
    fi

    if [[ -f "$theme_dir/themes/$selected/gtk-4.0/gtk.css" ]]; then
      ln -sfn "$theme_dir/themes/$selected/gtk-4.0/gtk.css" "$gtk4_dir/gtk.css"
    fi

    if [[ -d "$theme_dir/themes/$selected/kvantum" ]]; then
      if [[ -L "$kvantum_theme" || -e "$kvantum_theme" ]]; then
        rm -rf "$kvantum_theme"
      fi

      ln -sfn "$theme_dir/themes/$selected/kvantum" "$kvantum_theme"
    fi
  '';
}
