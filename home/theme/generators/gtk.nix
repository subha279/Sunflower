{
  lib,
  themeData,
  themeNames,
  base16,
}:

let
  gtk3Template = ../templates/gtk-3.0.css.mustache;
  gtk4Template = ../templates/gtk-4.0.css.mustache;
  thunarTemplate = ../templates/thunar.css.mustache;

  themeToGtk3 =
    themeId:
    let
      palette = base16.toBase16 themeId;
    in
    base16.renderTemplate gtk3Template palette + "\n" + base16.renderTemplate thunarTemplate palette;

  themeToGtk4 = themeId: base16.renderTemplate gtk4Template (base16.toBase16 themeId);

  gtk3Themes = lib.genAttrs themeNames (themeId: {
    text = themeToGtk3 themeId;
  });

  gtk4Themes = lib.genAttrs themeNames (themeId: {
    text = themeToGtk4 themeId;
  });

  generatedGtk3Files = lib.mapAttrs' (
    themeId: file: lib.nameValuePair "sunflower/themes/${themeId}/gtk-3.0/gtk.css" file
  ) gtk3Themes;

  generatedGtk4Files = lib.mapAttrs' (
    themeId: file: lib.nameValuePair "sunflower/themes/${themeId}/gtk-4.0/gtk.css" file
  ) gtk4Themes;

in
{
  inherit
    themeToGtk3
    themeToGtk4
    generatedGtk3Files
    generatedGtk4Files
    ;
}
