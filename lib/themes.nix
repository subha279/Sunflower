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
      name = "Tela-circle-dark";
      package = "tela-circle-icon-theme";
    };

    # Cursor
    cursor = {
      name = "Bibata-Modern-Classic";
      package = "pkgs.bibata-cursors";
      size = 24; # 24 or 32 scale best on modern high-DPI displays
    };

    # UI
    ui = {
      borderWidth = 2;
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

in
{
  inherit global themes;
  theme = themes.${global.activeTheme};
}
