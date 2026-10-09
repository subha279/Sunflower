{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    # Android
    scrcpy
    android-tools

    cloudflared

    # Build / compilation
    gcc
    clang
    gnumake
    cmake
    pkg-config

    # Development utilities
    git-lfs
    shellcheck
    zed-editor
    opencode

    # Node / JavaScript
    nodejs
    pnpm

    # Python
    python3

    # Containers
    podman
    podman-compose

    # Debugging
    gdb
    strace
    lldb

    # Documentation / inspection
    man-pages
    man-pages-posix

    # C/C++ tooling
    clang-tools

  ];
}
