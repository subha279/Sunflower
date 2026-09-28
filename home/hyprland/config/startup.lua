hl.on("hyprland.start", function()
	-- Session Environment
	hl.exec_cmd(
		"dbus-update-activation-environment --systemd "
			.. "WAYLAND_DISPLAY "
			.. "XDG_CURRENT_DESKTOP "
			.. "XDG_SESSION_TYPE "
			.. "XDG_SESSION_DESKTOP "
			.. "HYPRLAND_INSTANCE_SIGNATURE "
			.. "QT_STYLE_OVERRIDE "
			.. "QT_QPA_PLATFORMTHEME "
			.. "XCURSOR_THEME "
			.. "XCURSOR_SIZE "
			.. "GDK_BACKEND "
			.. "&& systemctl --user start hyprland-session.target"
	)

	-- Wallpaper
	hl.exec_cmd("~/.config/hypr/scripts/restore-wallpaper.sh")
end)
