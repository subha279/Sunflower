-- Decoration
-- Load Active Sunflower Theme
local home = os.getenv("HOME")
local themePath = home .. "/.config/sunflower/active-theme.lua"
local ok, theme = pcall(dofile, themePath)

if not ok or not theme then
	local fallback = home .. "/.config/sunflower/default-theme.lua"
	ok, theme = pcall(dofile, fallback)
end

if not ok or not theme then
	error("Sunflower: unable to load theme in decoration.lua")
end

local ui = theme.ui
local colors = theme.colors

if not ui then
	error("Sunflower: theme has no valid 'ui' table")
end

if not colors then
	error("Sunflower: theme has no valid 'colors' table")
end

local shadowAlpha = string.format("%02x", math.floor((ui.shadowOpacity or 0.20) * 255 + 0.5))

local function stripHash(color)
	if color == nil then
		return "000000"
	end

	return color:gsub("^#", "")
end

local function rgba(color, alpha)
	return "rgba(" .. stripHash(color) .. alpha .. ")"
end

hl.config({
	decoration = {
		-- dim_inactive is off on purpose: inactive_opacity below already signals focus.
		dim_inactive = false,
		dim_around = 0.30,
		dim_special = 0.20,
		dim_strength = 0.1,

		-- Rounded Corners
		rounding = ui.radius or 10,
		rounding_power = 2,

		-- Window Opacity
		active_opacity = 1.0,
		inactive_opacity = ui.windowOpacity or 0.96,

		-- Shadows
		shadow = {
			enabled = true,
			range = 18,
			render_power = 4,
			sharp = false,

			-- Theme-aware shadow color
			color = rgba(colors.backgroundDark or colors.background, shadowAlpha),
		},

		-- Blur
		blur = {
			enabled = true,
			size = 8,
			passes = 3,
			vibrancy = 0.18,
			vibrancy_darkness = 0.0,
			brightness = 1.0,
			contrast = 1.8,
			noise = 0.01,
			popups = true,
			special = 0,
			new_optimizations = true,
			ignore_opacity = true,
			xray = true,
		},
	},
})
