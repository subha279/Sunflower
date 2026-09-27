<div align="center">

  <!-- Dynamic Animated Banner -->
  <a href="https://github.com/subha279/Sunflower">
    <img src="https://readme-typing-svg.demolab.com?font=JetBrains+Mono&weight=700&size=38&duration=2800&pause=1000&color=CBA6F7&center=true&vCenter=true&width=680&lines=%F0%9F%8C%BB+Sunflower;" alt="Sunflower Desktop Banner" />
  </a>

  <p align="center">
    <a href="https://github.com/subha279/Sunflower"><img src="https://img.shields.io/badge/NixOS-26.05-7E7DFF?style=flat-square&logo=nixos&logoColor=white" alt="NixOS Base"></a>
    <a href="https://github.com/subha279/Sunflower"><img src="https://img.shields.io/badge/Hyprland-Lua-58E1FF?style=flat-square&logo=lua&logoColor=white" alt="Hyprland Lua"></a>
    <a href="https://github.com/subha279/Sunflower"><img src="https://img.shields.io/badge/Quickshell-QML-BB86FC?style=flat-square&logo=qt&logoColor=white" alt="Quickshell QML"></a>
  </p>

  <p align="center">
    <a href="#-showcase">Showcase</a> •
    <a href="#-features">Features</a> •
    <a href="#-quick-start">Quick Start</a> •
    <a href="#-architecture">Architecture</a> •
    <a href="#-theme-engine">Themes</a> •
    <a href="#-customization">Customization</a> •
    <a href="#-commands">Commands</a>
  </p>

</div>

---

## 📽️ Showcase

> **Visual Tour**: Watch the video preview below to see Sunflower in action. No static screenshots are shipped in this repository.

<div align="center">
  <a href="https://www.youtube.com/watch?v=J9286xiVBNk">
    <img src="https://img.youtube.com/vi/J9286xiVBNk/maxresdefault.jpg" alt="Sunflower desktop showcase video" width="760" style="border-radius: 8px;">
  </a>
</div>

---

## ✨ Features

### 🖥️ Desktop & Compositor

- **Lua-driven Hyprland**: Modular config structured under `home/hyprland/config/`.
- **Quickshell Unified Desktop**: Replaces bar, launcher, and notification daemons with a unified QML surface.
- **Instant IPC Surfaces**: App launcher, theme picker, wallpaper switcher, clipboard history, and emoji picker mapped directly to <kbd>SUPER</kbd> chords.
- **Monotonic Animations**: Layer surfaces animate smoothly within the compositor without UI stutter.
- **Smart Wallpaper Persistence**: Managed state in `~/.cache/sunflower/current-wallpaper` restored via `restore-wallpaper.sh` over `awww`.

### 🎨 Theme Engine

- **Centralized Palette Engine**: Define colors once in `lib/colorschemes/`, dynamic generation propagates to Lua, JSON, Kitty, tmux, Starship, GTK, and Kvantum.
- **Instant Runtime Switching**: Press <kbd>SUPER</kbd> + <kbd>C</kbd> to switch colors dynamically without rebuilding your system.
- **Stylix Base**: Manages Base16 schemes, fonts, and cursors cleanly while disabling intrusive GTK/Qt overrides.

### 💻 Terminal & Workspaces

- **Kitty & Tmux**: Dynamic theme inclusion (`active-kitty.conf` & `active-tmux.conf`) with `fzf` and `zoxide` shell integration.
- **Zsh & Starship**: Custom prompt exports directly into generated `active-starship.toml`.
- **Neovim Ecosystem**: Treesitter, Telescope, completion plugins, and 18 LSP configurations under `home/neovim/config/lsp/`.

### ⚙️ System Architecture

- **NixOS Flake Host**: `nixosConfigurations.sunflower` backed by 24 system modules and 13 Home Manager modules.
- **Unified Manager (`setup.sh`)**: Interactive installer, dry runner, validator, updates, backups, and generations rollback manager.
- **Rich Typography**: JetBrainsMono Nerd Font baseline complemented by Iosevka, Caskaydia Cove, Fira Code, SF Mono, Comic Shanns, Maple Mono, Inter, and Noto Emoji.

---

## 🚀 Quick Start

> [!NOTE]
> **Prerequisites**: Ensure you are booted into a NixOS Installer ISO with active network connectivity.

```bash
git clone https://github.com/subha279/Sunflower.git ~/Sunflower
cd ~/Sunflower
./setup.sh
```

> [!CAUTION]
> **Important installation notes:**
>
> - **`git` is optional.** Clone it, download it, or copy the directory — the installer, the rebuilds and the updates all work without a `.git` directory. When one is present it is staged so the flake sees every file, and dropped automatically if the configuration only evaluates as a plain path.
> - **A failed install cleans up after itself.** Just run `./setup.sh` again: the installer releases every mount and swap left on the target by the previous attempt (the old `sudo swapoff -a` / `sudo umount -R /mnt` dance is done for you) and re-checks the disk before erasing anything.
> - **The configuration is validated before the disk is touched.** A run whose flake does not evaluate is cancelled with nothing changed. Check it anywhere, changing nothing, with `./setup.sh validate`.
> - **Identity is validated up front.** Hostname (RFC 1123, lowercased), username (no reserved names), email and timezone are checked as you answer them — not after the disk is gone.
> - **Large download size:** Review the package list before installing. The total size is currently a massive **7.5 GB**, as it includes extra packages you might not need. (A fix to optimize this size is coming soon). The installer keeps 10 GiB free for the build and refuses to start when the disk cannot hold it.
>
> **Contributions Welcome:** If you run into any other bugs or have ideas for improvements, please raise an issue on the repository to help make the script better!

### Installation Workflow

1. **Launch Manager**: `./setup.sh` presents an interactive menu. Option `1` triggers system bootstrap.
2. **Configure Identity**: User, git credentials, hostname, timezone, and local variables are written to `lib/variables.nix`.
3. **Partition & Build**: Partitioning (1 GiB ESP + ext4 root), hardware generation, flake validation, and target store closure building.
4. **Reboot**: Boot into your fresh GRUB generation.

---

## 🏗️ Architecture

```text
flake.nix (.#sunflower)
│
├─ hosts/sunflower ───────── Host setup & generated hardware-configuration.nix
├─ modules/* (24) ────────── Boot, networking, audio, graphics, NVIDIA, desktop, stylix...
└─ home/* (13, HM) ───────── Hyprland, Quickshell, Neovim, Shell, Themes, Kitty, Tmux...

lib/variables.nix ── Identity & Hardware IDs (Single source of truth)
lib/themes.nix ─┬── global.activeTheme ──► home/theme generators
                │                           ├─ active-theme / themes/*.json + *.lua
lib/colorschemes/                           ├─ active-kitty.conf / active-tmux.conf
(7 palettes)                                ├─ active-starship.toml
                                            └─ GTK / Kvantum assets
                                                       │
              ┌────────────────────────────────────────┘
              ▼
 Hyprland ◄── active-theme.lua      Quickshell ◄── themes/*.json
 Kitty ◄───── active-kitty.conf     tmux ◄────── active-tmux.conf
 Starship ◄── active-starship.toml  Neovim ◄──── sunflower.theme (lua)
```

---

## 🎨 Theme Engine

Centralized controls lie within `lib/themes.nix` and `lib/colorschemes/`:

| Action                  | How to Apply                                  | Effect                                                |
| ----------------------- | --------------------------------------------- | ----------------------------------------------------- |
| **Change Palette**      | Press <kbd>SUPER</kbd> + <kbd>C</kbd>         | Live runtime theme swap across terminal, shell, & bar |
| **Set Default Theme**   | Edit `global.activeTheme` in `lib/themes.nix` | Persists default palette across system rebuilds       |
| **Create Custom Theme** | Add `.nix` palette in `lib/colorschemes/`     | Auto-generated into system-wide configurations        |

---

## 🧩 Components Matrix

| Component               | Target Location           | Description / Function                                     |
| ----------------------- | ------------------------- | ---------------------------------------------------------- |
| **Host Configuration**  | `hosts/sunflower/`        | Hardware bindings, imports, and system hostname            |
| **System Modules**      | `modules/`                | Graphics, power management, fonts, audio, & virtualisation |
| **Hyprland Compositor** | `home/hyprland/`          | Modular Lua configs (keybinds, rules, animations, env)     |
| **Quickshell**          | `home/quickshell/config/` | Bar UI, launchers, pickers, & notification daemons         |
| **Theme System**        | `home/theme/`             | Code generators, activation hooks, & runtime swapper       |
| **Neovim**              | `home/neovim/`            | LSP configurations, plugins, and custom UI themes          |
| **Identity & Vars**     | `lib/variables.nix`       | Unified variables (User details, GPU Bus IDs)              |
| **Management CLI**      | `setup.sh`                | Maintenance, rollback, validation, & installer engine      |

---

## 🛠️ Customization Quick-Guide

| Goal                   | Target File                         | Action Required                                      |
| ---------------------- | ----------------------------------- | ---------------------------------------------------- |
| **Keybindings**        | `home/hyprland/config/keybinds.lua` | Edit & run `hyprctl reload`                          |
| **System Fonts**       | `modules/fonts/default.nix`         | Modify packages & rebuild system                     |
| **Quickshell Widgets** | `home/quickshell/config/`           | Edit QML & run `systemctl --user restart quickshell` |
| **Terminal Config**    | `home/kitty/config/kitty.conf`      | Edit config & trigger rebuild                        |
| **Shell Aliases**      | `home/zsh/aliases.nix`              | Modify aliases & restart shell session               |

---

## 💻 Commands Reference

All orchestration actions are executed from the repo root via `./setup.sh`:

```bash
./setup.sh check        # Run `nix flake check`
./setup.sh dry          # Dry-run build (.#sunflower)
./setup.sh rebuild      # Validate & rebuild system configuration
./setup.sh update       # Git pull & update flake inputs
./setup.sh validate     # Perform comprehensive config verification
./setup.sh maintain     # Open maintenance dashboard (GC, verify)
./setup.sh rollback     # Roll back to previous NixOS generation
./setup.sh generations  # View system generation history
```

> [!TIP]
> **Recommended Workflow**: Always execute `./setup.sh check` → `./setup.sh dry` → `./setup.sh rebuild` when testing configuration changes.

---

## 💡 Philosophy

- **Declarative Truth**: Identity defined in `lib/variables.nix`, colors in `lib/colorschemes/`. Zero duplication across modules.
- **Runtime Over Rebuilds**: Anything that can reload at runtime (themes, wallpapers, shell modules) re-reads states dynamically.
- **Safe State Transitions**: Dry builds gate rebuilds, installer verifies UEFI & UUID integrity, and destructive steps require manual verification.
- **Keyboard Precision**: Keybinds, pickers, and workspace navigation map to short ergonomic chords defined in `variables.lua`.

---

## 📜 Credits & Ecosystem

- **Base System**: [NixOS](https://nixos.org) (`nixos-26.05`) & [Home Manager](https://github.com/nix-community/home-manager)
- **Compositor & Shell**: [Hyprland](https://hyprland.org) & [Quickshell](https://quickshell.org)
- **Styling & Fonts**: [Stylix](https://github.com/danth/stylix), [Apple Fonts Overlay](https://github.com/Lyndeno/apple-fonts.nix)
- **Applications**: [Zen Browser](https://github.com/youwen5/zen-browser-flake), [Kitty](https://sw.kovidgoyal.net/kitty/), [Neovim](https://neovim.io), [tmux](https://github.com/tmux/tmux), [Starship](https://starship.rs), [awww](https://github.com/lyghxht/awww)

---

<div align="center">

<sub>🌻 Sunflower: Plant once, bloom everywhere.</sub>

</div>
