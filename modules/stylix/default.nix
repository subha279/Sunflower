{ pkgs, lib, ... }:

let

  # Sunflower Theme Source
  themeData = import ../../lib/themes.nix;
  activeTheme = themeData.theme;
  colors = activeTheme.colors;
  global = themeData.global;

  # Helpers
  # themes.nix stores colors as "#RRGGBB"; base16 wants them bare.
  hex = lib.removePrefix "#";

  # Resolve DOTTED package paths such as "maple-mono.truetype".
  pkgFromPath = path: lib.getAttrFromPath (lib.splitString "." path) pkgs;

  # Central Fonts
  interfaceFont = pkgFromPath global.fonts.interface.package;
  terminalFont = pkgFromPath global.fonts.terminal.package;
  emojiFont = pkgFromPath global.fonts.emoji.package;

  # Central Cursor
  cursorPackage = pkgFromPath global.cursor.package;

in
{
  stylix = {

    # Core
    enable = true;

    # Sunflower explicitly owns application-specific theming.
    autoEnable = false;

    # Derived, not hardcoded. See Polarity Detection in lib/themes.nix.
    polarity = themeData.polarity;

    # STATIC SUNFLOWER COLOR SOURCE
    base16Scheme = {
      scheme = activeTheme.name;
      author = "Sunflower (lib/themes.nix)";

      # Base ramp
      base00 = hex colors.background;
      base01 = hex colors.surface;
      base02 = hex colors.surfaceHover;
      base03 = hex colors.textMuted; # was border -> comments were invisible
      base04 = hex colors.textSecondary; # was textMuted -> ramp was shifted
      base05 = hex colors.text;
      # base06/base07 are the bright end of the foreground ramp.
      base06 = hex colors.terminalWhite;
      base07 = hex colors.terminalBrightWhite;

      # Semantic
      base08 = hex colors.error;
      base09 = hex colors.warning;
      base0A = hex colors.terminalYellow; # was a duplicate of warning
      base0B = hex colors.success;
      base0C = hex colors.terminalCyan;
      base0D = hex colors.info;
      base0E = hex colors.accent;
      base0F = hex colors.terminalMagenta; # was accentMuted -> near-background
    };

    # FONTS
    fonts = {
      sansSerif = {
        package = interfaceFont;
        name = global.fonts.interface.name;
      };

      serif = {
        package = interfaceFont;
        name = global.fonts.interface.name;
      };

      monospace = {
        package = terminalFont;
        name = global.fonts.terminal.name;
      };

      emoji = {
        package = emojiFont;
        name = global.fonts.emoji.name;
      };

      sizes = {
        applications = global.ui.fontSize;
        desktop = global.ui.fontSize;
        popups = global.ui.fontSize;
        terminal = global.ui.fontSize;
      };
    };

    # CURSOR
    cursor = {
      package = cursorPackage;
      name = global.cursor.name;
      size = global.cursor.size;
    };

    targets.gtk.enable = false;
    targets.qt.enable = false;
    targets.fontconfig.enable = true;
  };
}
