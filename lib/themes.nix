let
  global = {
    # Active theme
    activeTheme = "sunflower";

    # Fonts
    fonts = {
      interface = {
        name = "Inter";
        package = "inter";
      };

      terminal = {
        name = "JetBrainsMono Nerd Font";
        package = "nerd-fonts.jetbrains-mono";
      };

      emoji = {
        name = "Noto Color Emoji";
        package = "noto-fonts-color-emoji";
      };
    };

    # Icons
    icons = {
      name = "Papirus-Dark";
      package = "papirus-icon-theme";
    };

    # Cursor
    cursor = {
      name = "Bibata-Modern-Classic";
      package = "pkgs.bibata-cursors";
      size = 24; # 24 or 32 scale best on modern high-DPI displays
    };

    # UI
    ui = {
      borderWidth = 0;
      radius = 15;
      radiusSmall = 10;
      radiusLarge = 18;
      iconSize = 16;
      fontSize = 13;
      fontSizeSmall = 10;
      fontSizeLarge = 16;

      glassOpacity = 0.50;
      surfaceOpacity = 0.18;
      glassLuminosity = 0.20;
      glassGradientOpacity = 0.055;
      glassGrainOpacity = 0.0;

      glassSpecularOpacity = 0.0;
      glassLensOpacity = 0.0;
      glassDepthOpacity = 0.0;
      glassRimOpacity = 0.0;
      glassClarity = 0.14;

      shadowOpacity = 0.24;
      windowOpacity = 0.96;
      terminalOpacity = 0.52;
      editorFloatBlend = 12;

      clock = {
        hour = "foreground";
        separator = "foregroundMuted";
        minute = "accent";
        second = "foregroundFaint";
      };
    };
  };

  # Automatically load every *.nix file in ./themes.
  colorschemeDir = ./themes;
  colorschemeFiles = builtins.filter (name: builtins.match ".*\\.nix" name != null) (
    builtins.attrNames (builtins.readDir colorschemeDir)
  );

  themes = builtins.listToAttrs (
    map (
      file:
      let
        name = builtins.replaceStrings [ ".nix" ] [ "" ] file;
      in
      {
        inherit name;
        value = import (colorschemeDir + "/${file}");
      }
    ) colorschemeFiles
  );

  theme = themes.${global.activeTheme};

  # Polarity Detection (ITU-R BT.601 perceived brightness of the background).
  hexToInt = s: (builtins.fromTOML "v = 0x${s}").v;
  bgHex =
    if builtins.substring 0 1 theme.colors.background == "#" then
      builtins.substring 1 6 theme.colors.background
    else
      theme.colors.background;

  bgBrightness =
    (
      hexToInt (builtins.substring 0 2 bgHex) * 299
      + hexToInt (builtins.substring 2 2 bgHex) * 587
      + hexToInt (builtins.substring 4 2 bgHex) * 114
    )
    / 1000;

in
{
  inherit global themes theme;

  polarity = if bgBrightness > 127 then "light" else "dark";
}
