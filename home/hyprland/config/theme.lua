-- Sunflower Hyprland Theme

-- Paths
local home = os.getenv("HOME")
local activeThemePath = home .. "/.config/sunflower/active-theme.lua"
-- Fallback to the default palette declared in lib/themes.nix and materialised
-- by the theme generators as ~/.config/sunflower/default-theme.lua.
local fallbackThemePath = home .. "/.config/sunflower/default-theme.lua"

-- Load Active Theme
local ok = false
local theme = nil

-- Prefer currently selected theme
local activeFile = io.open(activeThemePath, "r")

if activeFile then
	activeFile:close()
	ok, theme = pcall(dofile, activeThemePath)
end

-- Fallback to the default theme
if not ok or not theme then
	ok, theme = pcall(dofile, fallbackThemePath)
end

-- Fail clearly if no theme is available
if not ok or not theme then
	error(
		"Sunflower: unable to load theme.\n"
			.. "Active theme: "
			.. activeThemePath
			.. "\n"
			.. "Fallback theme: "
			.. fallbackThemePath
	)
end

-- Color Helpers
local function stripHash(color)
	if color == nil then
		return "000000"
	end

	return color:gsub("^#", "")
end

-- Convert #RRGGBB -> rgba(RRGGBBAA)

local function rgba(color, alpha)
	return "rgba(" .. stripHash(color) .. (alpha or "ff") .. ")"
end

-- Theme Colors

local colors = theme.colors

if type(colors) ~= "table" then
	error("Sunflower: theme has no valid 'colors' table")
end

-- Hyprland Theme

hl.config({
	general = {
		col = {
			-- Active Window Border
			active_border = {
				colors = {
					rgba(colors.accent, "ff"),
					rgba(colors.accentActive, "ff"),
				},
				angle = 45,
			},

			-- Inactive Window Border
			inactive_border = rgba(colors.border, "cc"),
		},
	},
})
