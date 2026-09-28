-- Window Rules
-- 1. Global

-- Suppress Maximize Requests
hl.window_rule({
	name = "suppress-maximize-events",
	match = { class = ".*" },
	suppress_event = "maximize",
})

-- Global Modal Dialogs
hl.window_rule({
	name = "modal-dialogs",
	match = { modal = true },
	float = true,
	center = true,
	rounding = 10,
	dim_around = true,
	animation = "popin 90%",
})

-- XWayland Dragging Fix
hl.window_rule({
	name = "fix-xwayland-drags",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},
	no_focus = true,
})

-- 2. Generic Dialogs
-- File Choosers
hl.window_rule({
	name = "file-chooser-dialogs",
	match = {
		title = "^(Open File|Open Files|Open Folder|Open Document|Open Image|Save|Save As|Save File|Save Image|Save Video|Save Document|Save Project|Select File|Select Files|Select Folder|Select Directory|Select a File|Choose File|Choose Files|Choose a file|File Upload|Add Files|Add Folder|Import File|Export Image|Export As)( .*)?$",
	},
	float = true,
	center = true,
	size = "900 600",
	rounding = 10,
	dim_around = true,
})

-- File Conflicts
hl.window_rule({
	name = "file-conflict-dialogs",
	match = {
		title = "^(Confirm to replace files|Confirm to replace|Replace file|Replace files|File Exists|Merge Folders?)( .*)?$",
	},
	float = true,
	center = true,
	rounding = 10,
	dim_around = true,
})

-- File Operation Progress
hl.window_rule({
	name = "file-progress-dialogs",
	match = {
		title = "^(File Operation Progress|Copying files|Moving files|Deleting files|Transferring files|Extracting files|Compressing files|Emptying Trash)( .*)?$",
	},
	float = true,
	move = "monitor_w-520 80",
	rounding = 10,
	no_focus = true,
})

-- Short Confirmations
hl.window_rule({
	name = "confirmation-dialogs",
	match = {
		title = "^(Rename|Rename File|Rename Folder|Create New Folder|Create Folder|New Folder|Confirm|Confirmation|Question|Warning|Error|Delete|Permanently Delete)( .*)?$",
	},
	float = true,
	center = true,
	rounding = 10,
	dim_around = true,
})

-- Properties
hl.window_rule({
	name = "properties-dialog",
	match = { title = "^(Properties|.* Properties)$" },
	float = true,
	center = true,
	size = "500 600",
	rounding = 10,
	dim_around = true,
})

-- Preferences and About
hl.window_rule({
	name = "preferences-dialogs",
	match = {
		title = "^(Preferences|Settings|Options|Configuration|Keyboard Shortcuts|About)( .*)?$",
	},
	float = true,
	center = true,
	size = "800 600",
	rounding = 10,
	dim_around = true,
	animation = "popin 90%",
})

-- 3. System and Shell UI
-- Polkit Authentication Agent
hl.window_rule({
	name = "polkit-agent",
	match = {
		class = "^(polkit-kde-authentication-agent-1|org\\.kde\\.polkit-kde-authentication-agent-1|polkit-gnome-authentication-agent-1)$",
	},
	float = true,
	center = true,
	size = "480 260",
	rounding = 10,
	dim_around = true,
	animation = "popin 90%",
})

-- XDG Desktop Portal
hl.window_rule({
	name = "xdg-desktop-portal",
	match = { class = "^xdg-desktop-portal-gtk$" },
	float = true,
	center = true,
	size = "700 400",
	rounding = 10,
	dim_around = true,
	animation = "popin 90%",
})

-- Bluetooth Manager
hl.window_rule({
	name = "blueman-manager",
	match = { class = "^\\.blueman-manager-wrapped$" },
	float = true,
	center = true,
	size = "760 560",
	rounding = 10,
	opacity = "0.90 0.90",
	dim_around = true,
	animation = "popin 90%",
})

hl.window_rule({
	name = "blueman-dialogs",
	match = {
		class = "^(\\.?blueman-(adapters|services|sendto)(-wrapped)?)$",
	},
	float = true,
	center = true,
	size = "600 460",
	rounding = 10,
	opacity = "0.95 0.95",
	dim_around = true,
	animation = "popin 90%",
})

-- NetworkManager Connection Editor
hl.window_rule({
	name = "network-manager",
	match = { class = "^nm-connection-editor$" },
	float = true,
	center = true,
	size = "500 600",
	rounding = 10,
	opacity = "0.95 0.95",
	dim_around = true,
	animation = "popin 90%",
})

-- Pavucontrol
hl.window_rule({
	name = "pavucontrol",
	match = { class = "^org\\.pulseaudio\\.pavucontrol$" },
	float = true,
	center = true,
	size = "900 650",
	rounding = 10,
	opacity = "0.97 0.97",
	dim_around = true,
	animation = "popin 90%",
})

-- Appearance Tools
hl.window_rule({
	name = "appearance-tools",
	match = { class = "^(kvantummanager|org\\.kde\\.kvantummanager)$" },
	float = true,
	center = true,
	size = "900 650",
	rounding = 10,
	dim_around = true,
	animation = "popin 90%",
})

-- 4. Applications
-- Zen Browser
hl.window_rule({
	name = "zen-browser",
	match = { class = "^zen$" },
	opacity = "0.92 override 0.92 override 0.92 override",
	xray = true,
})

hl.window_rule({
	name = "zen-google-auth",
	match = { class = "^zen$", title = "Google Accounts" },
	float = true,
	center = true,
	size = "700 700",
	rounding = 10,
	dim_around = true,
	animation = "popin 90%",
})

hl.window_rule({
	name = "zen-picture-in-picture",
	match = { class = "^zen$", title = "Picture-in-Picture" },
	float = true,
	size = "640 360",
	move = "monitor_w-664 monitor_h-408",
	rounding = 10,
})

-- Thunar
hl.window_rule({
	name = "thunar-bulk-rename",
	match = { class = "^[tT]hunar$", title = "^Bulk Rename( .*)?$" },
	float = true,
	center = true,
	size = "800 500",
	rounding = 10,
	dim_around = true,
})

-- Archive Manager
hl.window_rule({
	name = "file-roller",
	match = { class = "^(file-roller|org\\.gnome\\.FileRoller)$" },
	float = true,
	center = true,
	size = "800 550",
	rounding = 10,
	dim_around = true,
	animation = "popin 90%",
})

-- Image Viewers & Annotation
hl.window_rule({
	name = "gwenview",
	match = { class = "^org\\.kde\\.gwenview$" },
	float = true,
	center = true,
	size = "1280 800",
	rounding = 10,
	opacity = "1.0 override 1.0 override",
})

hl.window_rule({
	name = "imagemagick-display",
	match = { class = "^display-im6\\.q16$" },
	float = true,
	center = true,
	opacity = "1.0 override 1.0 override",
})

hl.window_rule({
	name = "swappy",
	match = { class = "^swappy$" },
	float = true,
	center = true,
	size = "1200 800",
	rounding = 10,
	opacity = "1.0 override 1.0 override",
	animation = "popin 90%",
})

-- Editors and Office
hl.window_rule({
	name = "code-editors",
	match = { class = "^(dev\\.zed\\.Zed|obsidian)$" },
	opacity = "1.0 override 1.0 override",
})

hl.window_rule({
	name = "libreoffice",
	match = { class = "^(libreoffice.*|soffice.*)$" },
	opacity = "1.0 override 1.0 override",
})

-- Virtualisation
hl.window_rule({
	name = "virt-manager",
	match = { class = "^(\\.?virt-manager.*)$" },
	float = true,
	center = true,
	size = "1100 700",
	rounding = 10,
})

hl.window_rule({
	name = "virt-viewer",
	match = { class = "^(\\.?(virt|remote)-viewer.*)$" },
	float = true,
	center = true,
	size = "1280 800",
	opacity = "1.0 override 1.0 override",
})

-- OBS Studio
hl.window_rule({
	name = "obs-studio",
	match = { class = "^com\\.obsproject\\.Studio$" },
	opacity = "1.0 override 1.0 override",
	xray = true,
})

hl.window_rule({
	name = "obs-studio-dialogs",
	match = {
		class = "^com\\.obsproject\\.Studio$",
		title = "^(Settings|Filters|Properties for .*|Auto-Configuration Wizard|Output Timer|Stats|Docks)( .*)?$",
	},
	float = true,
	center = true,
	size = "960 680",
	rounding = 10,
	dim_around = true,
})

-- DaVinci Resolve
hl.window_rule({
	name = "davinci-resolve",
	match = { class = "^resolve$" },
	opacity = "1.0 override 1.0 override",
	xray = true,
})

-- MPV
hl.window_rule({
	name = "mpv-no-animation",
	match = { class = "^mpv$" },
	no_anim = true,
})

-- Design Tools
hl.window_rule({
	name = "gimp",
	match = { class = "^(gimp.*|GNU Image Manipulation Program)$" },
	opacity = "1.0 override 1.0 override",
})

hl.window_rule({
	name = "blender",
	match = { class = "^[Bb]lender$" },
	opacity = "1.0 override 1.0 override",
})

-- Steam & Games
hl.window_rule({
	name = "steam",
	match = { class = "^steam$" },
	opacity = "1.0 override 1.0 override",
})

hl.window_rule({
	name = "steam-dialogs",
	match = {
		class = "^steam$",
		title = "^(Friends List|Steam Settings|Steam - News.*|Screenshot Uploader|Special Offers|Sign in to Steam)( .*)?$",
	},
	float = true,
	center = true,
	size = "700 800",
	rounding = 10,
})

hl.window_rule({
	name = "games",
	match = { class = "^(steam_app_\\d+|steam_proton|\\.?gamescope.*)$" },
	opacity = "1.0 override 1.0 override",
	xray = true,
})

-- Hyprland Run Dialog
hl.window_rule({
	name = "hyprland-run",
	match = { class = "^hyprland-run$" },
	float = true,
	move = "20 monitor_h-120",
	rounding = 10,
})
