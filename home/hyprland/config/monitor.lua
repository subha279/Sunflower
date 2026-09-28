-- Monitor Configuration

-- Laptop Display
-- Stays enabled: scripts/monitor.sh disables it while the lid is closed and
-- brings it back when the lid opens (see "Lid Switch" below).
-- mode/position/scale must match PANEL_* in scripts/monitor.sh.
hl.monitor({
	output = "eDP-1",
	mode = "preferred",
	position = "auto",
	--	scale = 1.25,
})

-- External Acer VG240Y M3
hl.monitor({
	output = "HDMI-A-1",
	mode = "1920x1080@180.00301",
	--position = "1920x0",
	position = "0x0",
	scale = 1,
})

-- Lid Switch
-- Turns the internal panel off while the lid is closed and back on when it is
-- opened. Detection of internal/external outputs lives in scripts/monitor.sh.
local vars = require("config.variables")
local script = vars.scriptDir .. "/monitor.sh"

-- Kernel switch name, identical on every ACPI laptop (see `hyprctl devices`)
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd(script .. " close"), { locked = true })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd(script .. " open"), { locked = true })

-- Re-apply the lid state when it cannot come from a switch event
hl.on("hyprland.start", function()
	hl.exec_cmd(script .. " sync")
end)

hl.on("config.reloaded", function()
	hl.exec_cmd(script .. " sync")
end)

-- Docking / undocking changes which display has to stay on
hl.on("monitor.added", function()
	hl.exec_cmd(script .. " sync")
end)

hl.on("monitor.removed", function()
	hl.exec_cmd(script .. " sync")
end)
