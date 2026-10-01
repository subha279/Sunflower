{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [

    # Browser
    zen-browser

    # File Manager
    shared-mime-info
    ffmpegthumbnailer

    # Archives
    p7zip
    unar

    # Archive Manager
    file-roller

    # Audio
    pavucontrol

    # Theming
    kdePackages.qtstyleplugin-kvantum

    # Network
    networkmanagerapplet

    # Screenshots
    grim
    slurp
    swappy

    # Image Viewer / Basic Editor
    kdePackages.gwenview
    imagemagick

    # Authentication
    kdePackages.polkit-kde-agent-1

    # Wallpaper
    awww

    # Notifications
    libnotify

    # Desktop Utilities
    xdg-utils

    # Content Creation
    (pkgs.obs-studio.override {
      cudaSupport = true;
    })

    ffmpeg
    libreoffice
    gimp
    blender

    # Text Editor
    vis

  ];
}
