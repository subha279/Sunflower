{ ... }:

{
  programs.tmux = {
    enable = true;
  };

  xdg.configFile = {
    "tmux/tmux.conf".source = ./config/tmux.conf;
    "tmux/theme".source = ./config/theme;
  };
}
