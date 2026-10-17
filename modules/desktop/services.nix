{ pkgs, ... }:

{
  # Desktop Services
  services.gvfs.enable = true;
  services.gnome.gnome-keyring.enable = true;
  services.udisks2.enable = true;

  # Thunar
  programs.thunar = {
    enable = true;
    plugins = with pkgs; [
      thunar-volman
      thunar-archive-plugin
      thunar-media-tags-plugin
    ];
  };

  # Settings persistence for Thunar.
  programs.xfconf.enable = true;
  # Thumbnails.
  services.tumbler.enable = true;
  # Ollama
  services.ollama.enable = true;
}
