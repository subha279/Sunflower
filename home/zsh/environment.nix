{ ... }:

{
  # Shell / Developer Environment

  home.sessionVariables = {
    # Editor
    EDITOR = "nvim";
    VISUAL = "nvim";

    # Pager
    PAGER = "less";
    LESS = "-R";
    MANPAGER = "less -R";

    # Applications
    BROWSER = "zen";
    TERMINAL = "kitty";

    # Virtualization
    LIBVIRT_DEFAULT_URI = "qemu:///system";
  };

  # User PATH
  home.sessionPath = [
    "$HOME/.local/bin"
  ];

  # Direnv
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;

    nix-direnv = {
      enable = true;
    };
  };
}
