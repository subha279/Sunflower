-- Environment Variables
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Wayland
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Qt Applications
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")

-- GTK Applications
hl.env("GDK_BACKEND", "wayland,x11")

-- Java Applications
hl.env("_JAVA_AWT_WM_NONREPARENTING", "1")

-- Default Applications
hl.env("EDITOR", "nvim")
hl.env("BROWSER", "zen")
hl.env("TERMINAL", "kitty")
