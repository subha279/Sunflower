-- General Configuration

-- Load Active Sunflower Theme

local home = os.getenv("HOME")
local themePath = home .. "/.config/sunflower/active-theme.lua"
local ok, theme = pcall(dofile, themePath)

if not ok or not theme then
	local fallback = home .. "/.config/sunflower/default-theme.lua"

	ok, theme = pcall(dofile, fallback)
end

if not ok or not theme then
	error("Sunflower: unable to load theme in general.lua")
end

local ui = theme.ui

-- General
hl.config({

	general = {
		gaps_in = 5,
		gaps_out = 10,

		-- Borders
		border_size = ui.borderWidth,

		-- Resize
		resize_on_border = true,

		-- Tearing
		allow_tearing = false,

		-- Layout
		layout = "dwindle",
	},
})
