{ ... }:

{
  # XDG
  xdg = {
    portal = {
      enable = true;
    };

    mime.enable = true;
    autostart.enable = true;
    icons.enable = true;
    menus.enable = true;

    # Default Applications
    mime.defaultApplications =
      let
        browser = "zen.desktop";
        images = "org.kde.gwenview.desktop";
        video = "mpv.desktop";
        files = "thunar.desktop";
        archive = "org.gnome.FileRoller.desktop";
      in
      {
        # Browser
        "text/html" = browser;
        "x-scheme-handler/http" = browser;
        "x-scheme-handler/https" = browser;
        "x-scheme-handler/about" = browser;
        "x-scheme-handler/unknown" = browser;

        # Documents
        "application/pdf" = browser;

        # File manager
        "inode/directory" = files;

        # Images
        "image/png" = images;
        "image/jpeg" = images;
        "image/webp" = images;
        "image/gif" = images;
        "image/tiff" = images;
        "image/bmp" = images;
        "image/avif" = images;

        # Vector images
        "image/svg+xml" = browser;

        # Video
        "video/mp4" = video;
        "video/x-matroska" = video;
        "video/webm" = video;
        "video/quicktime" = video;
        "video/x-msvideo" = video;

        # Audio
        "audio/mpeg" = video;
        "audio/flac" = video;
        "audio/x-wav" = video;
        "audio/ogg" = video;

        # Archives
        "application/zip" = archive;
        "application/x-7z-compressed" = archive;
        "application/x-tar" = archive;
        "application/gzip" = archive;
        "application/x-xz" = archive;
        "application/vnd.rar" = archive;
      };
  };
}
