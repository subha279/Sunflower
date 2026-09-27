{
  lib,
  themeData,
  themeNames,
  ...
}:

let
  themeToStarship =
    themeId:
    let
      theme = themeData.themes.${themeId};
      colors = theme.colors;
    in
    ''
      add_newline = false
      command_timeout = 1000
      scan_timeout = 30
      follow_symlinks = false
      palette = "sunflower"

      format = """\
      $directory\
      ''${custom.giturl}\
      $git_branch\
      ''${custom.git_worktree}\
      $git_status\
      $package\
      $c\
      $python\
      $cmd_duration\
      $character"""

      [palettes.sunflower]
      bg = "${colors.background}"
      surface = "${colors.surface}"
      surface2 = "${colors.surfaceHover}"
      surface3 = "${colors.surfaceActive}"
      text = "${colors.text}"
      text_soft = "${colors.textSecondary}"
      muted = "${colors.textMuted}"
      dim = "${colors.textMuted}"
      purple = "${colors.accent}"
      purple_bright = "${colors.accentHover}"
      purple_soft = "${colors.accentMuted}"
      purple_dark = "${colors.border}"
      blue = "${colors.terminalBlue}"
      cyan = "${colors.terminalCyan}"
      green = "${colors.success}"
      yellow = "${colors.warning}"
      orange = "${colors.warning}"
      red = "${colors.error}"
      pink = "${colors.terminalMagenta}"

      [os]
      disabled = false
      style = "bold text"
      format = "[$symbol ]($style)"

      [os.symbols]
      NixOS = ""
      Macos = ""
      Windows = "󰍲"

      [directory]
      style = "bold text"
      format = "[$path]($style)[$read_only]($read_only_style) "
      home_symbol = "~"
      truncation_length = 3
      truncate_to_repo = false
      truncation_symbol = "…/"
      read_only = " 󰌾"
      read_only_style = "bold red"

      [custom.giturl]
      description = "Display symbol for remote Git server"

      command = """
      GIT_REMOTE=$(git remote get-url origin 2>/dev/null)
      case "$GIT_REMOTE" in
        *github*)
          echo ""
          ;;
        *gitlab*)
          echo ""
          ;;
        *bitbucket*)
          echo ""
          ;;
        *git*)
          echo ""
          ;;
        *)
          echo ""
          ;;
      esac
      """

      when = "git remote get-url origin 2>/dev/null"
      format = "[$output](bold purple) "
      require_repo = true
      ignore_timeout = true

      [git_branch]
      symbol = " "
      format = "[](purple)[ $symbol$branch ](bold bg bg:purple)[](purple) "

      [custom.git_worktree]
      description = "Show indicator when inside a Git worktree"

      command = """
      if git rev-parse --git-dir >/dev/null 2>&1; then
        common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
        git_dir=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)

        if [ "$common_dir" != "$git_dir" ]; then
          echo "⛓"
        fi
      fi
      """

      when = """test "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" != "$(git rev-parse --path-format=absolute --git-dir 2>/dev/null)""""
      format = "[$output](bold purple) "
      style = "bold purple"
      require_repo = true
      ignore_timeout = true

      [git_status]
      style = "bold text"
      format = "[$untracked$staged$modified$renamed$deleted$conflicted$stashed$typechanged$ahead_behind]($style)"
      untracked = "[?](bold red) "
      staged = "[+](bold green) "
      modified = "[!](bold yellow) "
      renamed = "[󰷫](bold blue) "
      deleted = "[󱂥](bold red) "
      conflicted = "[󰜺](bold red) "
      stashed = "[≡](bold purple) "
      typechanged = "[ ](bold cyan) "
      ahead = "[⇡''${count}](bold cyan) "
      behind = "[⇣''${count}](bold orange) "
      diverged = "[⇕⇡''${ahead_count}⇣''${behind_count}](bold pink) "
      up_to_date = ""

      [package]
      disabled = false
      symbol = "󰏗 "
      style = "bold purple"
      format = "[$symbol$version]($style) "

      [c]
      symbol = " "
      style = "bold blue"
      format = "[$symbol($version)]($style) "

      [python]
      symbol = " "
      style = "bold yellow"
      format = "[$symbol($version)]($style) "

      [time]
      disabled = true
      time_format = "%R"
      style = "bold muted"
      format = "[󰥔 $time]($style) "

      [cmd_duration]
      min_time = 1000
      style = "bold muted"
      format = "[󰔟 $duration]($style) "

      [character]
      success_symbol = "[➜](bold purple)"
      error_symbol = "[➜](bold red)"
      vimcmd_symbol = "[➜](bold cyan)"
      vimcmd_replace_one_symbol = "[➜](bold pink)"
      vimcmd_replace_symbol = "[➜](bold pink)"
      vimcmd_visual_symbol = "[➜](bold purple)"
    '';

  starshipThemeFiles = lib.genAttrs themeNames (themeId: {
    text = themeToStarship themeId;
  });

  generatedStarshipFiles = lib.mapAttrs' (
    themeId: file: lib.nameValuePair "sunflower/themes/${themeId}.starship.toml" file
  ) starshipThemeFiles;

in
{
  inherit
    themeToStarship
    starshipThemeFiles
    generatedStarshipFiles
    ;
}
