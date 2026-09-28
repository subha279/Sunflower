{ lib, pkgs, ... }:

let
  themeData = import ../../lib/themes.nix;
  themeNames = builtins.attrNames themeData.themes;

  defaultThemeId = themeData.global.activeTheme;

  # GTK + Kvantum + Base16 helpers
  generators = import ./generators.nix {
    inherit lib themeData themeNames;
  };

  # Lua + JSON
  data = import ./generators/data.nix {
    inherit lib themeData themeNames;
  };

  # Kitty
  kitty = import ./generators/kitty.nix {
    inherit lib themeData themeNames;
  };

  # tmux
  tmux = import ./generators/tmux.nix {
    inherit lib themeData themeNames;
  };

  # Starship
  starship = import ./generators/starship.nix {
    inherit lib themeData themeNames;
  };

  pkgFromPath = path: lib.getAttrFromPath (lib.splitString "." path) pkgs;
  iconPackage = pkgFromPath themeData.global.icons.package;
  iconThemeName = themeData.global.icons.name;

  themeList = builtins.concatStringsSep "\n" (
    map (
      themeId:
      let
        theme = themeData.themes.${themeId};
      in
      "${themeId}\t${theme.name}"
    ) themeNames
  );

  # All generated theme files.
  generatedThemeFiles =
    data.generatedLuaFiles
    // data.generatedJsonFiles
    // kitty.generatedKittyFiles
    // tmux.generatedTmuxFiles
    // starship.generatedStarshipFiles
    // generators.generatedGtk3Files
    // generators.generatedGtk4Files
    // generators.generatedKvantumConfigFiles
    // generators.generatedKvantumSvgFiles;

in
{
  imports = [
    ./activation.nix
  ];

  home.packages = [
    iconPackage
  ];

  gtk = {
    enable = true;

    iconTheme = {
      package = iconPackage;
      name = iconThemeName;
    };
  };

  stylix.targets.gtk.enable = false;
  stylix.targets.qt.enable = false;
  stylix.targets.fontconfig.enable = true;

  xdg.configFile = {
    "sunflower/themes.json".text = builtins.toJSON themeData;
    "sunflower/themes.list".text = themeList + "\n";
    "sunflower/default-theme".text = defaultThemeId + "\n";
    "sunflower/default-theme.lua" = data.luaThemeFiles.${defaultThemeId};
  }
  // generatedThemeFiles;

  home.file.".local/bin/sunflower-theme" = {
    executable = true;
    source = ./scripts/sunflower-theme;
  };
}
