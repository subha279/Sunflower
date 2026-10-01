{ pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    sideloadInitLua = true;
    plugins = with pkgs.vimPlugins; [
      # Completion
      blink-cmp

      # Syntax / Treesitter
      nvim-treesitter.withAllGrammars
      nvim-colorizer-lua

      # Search / Navigation
      telescope-nvim
      telescope-fzf-native-nvim
      plenary-nvim
      nvim-web-devicons

      # Git
      gitsigns-nvim

      # Formatting / Linting
      conform-nvim
      nvim-lint

      # UI
      which-key-nvim
      lualine-nvim
      snacks-nvim

      # File Manager
      nvim-tree-lua

      # Dashboard
      alpha-nvim
    ];

    # Tools available directly to Neovim.
    extraPackages = with pkgs; [

      # LSP
      # QML language server, formatter, and linter.
      qt6.qtdeclarative
      lua-language-server
      rust-analyzer
      typescript-language-server
      pyright
      clang-tools
      nixd
      bash-language-server
      vscode-langservers-extracted
      yaml-language-server
      marksman
      tailwindcss-language-server
      dockerfile-language-server
      taplo

      # Formatters
      stylua
      prettier
      ruff
      nixfmt
      shfmt
      eslint_d
      shellcheck
      rustfmt

      # C / C++ development
      gcc
      gdb
      cmake
      pkg-config

      # Git / VCS
      lazygit
    ];
  };

  xdg.configFile."nvim".source = ./config;
}
