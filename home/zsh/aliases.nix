{ ... }:

{
  programs.zsh.shellAliases = {

    # Listing
    ls = "eza --icons --group-directories-first";
    ll = "eza -lah --icons --group-directories-first";
    la = "eza -a --icons --group-directories-first";
    lt = "eza --tree --icons --group-directories-first";
    tree = "eza --tree --icons --group-directories-first";

    # Navigation
    ".." = "cd ..";
    "..." = "cd ../..";
    "...." = "cd ../../..";

    # Editors
    v = "nvim";
    vim = "nvim";
    sv = "sudo -E nvim";

    # Utilities
    c = "clear";
    df = "df -h";
    du = "du -h";
    diff = "diff --color=auto";

    # Git
    gs = "git status";
    gd = "git diff";
    gl = "git log --oneline --graph --decorate";
    ga = "git add";
    gc = "git commit";
    gp = "git push";
    gpl = "git pull --ff-only";

    # Development
    nd = "nix develop -c zsh";
    ssh = "TERM=xterm-256color ssh";
    rebuild = "sudo nixos-rebuild switch --flake '.#sunflower'";
  };
}
