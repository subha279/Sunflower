{ ... }:

let
  vars = import ../lib/variables.nix;
in

{
  imports = [
    ./git
    ./zsh
    ./kitty
    ./tmux
    ./fastfetch
    ./ssh
    ./xdg
    ./neovim
    ./hyprland
    ./quickshell
    ./obsidian
    ./theme
    ./mpv
    ./thunar
  ];

  home.username = vars.user.username;
  home.homeDirectory = "/home/${vars.user.username}";
  home.stateVersion = "26.05";
  programs.home-manager.enable = true;
}
