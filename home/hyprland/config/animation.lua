-- Animations
hl.config({
	animations = {
		enabled = true,
	},
})

-- Curves
hl.curve("easeOutExpo", { type = "bezier", points = { { 0.16, 1.00 }, { 0.30, 1.00 } } })
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.22, 1.00 }, { 0.36, 1.00 } } })
hl.curve("easeInQuint", { type = "bezier", points = { { 0.64, 0.00 }, { 0.78, 0.00 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.00 }, { 0.35, 1.00 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.50, 0.50 }, { 0.75, 1.00 } } })

-- Root
hl.animation({
	leaf = "global",
	enabled = true,
	speed = 3.0,
	bezier = "easeOutQuint",
})

-- Windows
hl.animation({
	leaf = "windows",
	enabled = true,
	speed = 3.0,
	bezier = "easeOutQuint",
	style = "popin 96%",
})

hl.animation({
	leaf = "windowsIn",
	enabled = true,
	speed = 2.8,
	bezier = "easeOutExpo",
	style = "popin 96%",
})

hl.animation({
	leaf = "windowsOut",
	enabled = true,
	speed = 1.8,
	bezier = "easeInQuint",
	style = "popin 96%",
})

hl.animation({
	leaf = "windowsMove",
	enabled = true,
	speed = 2.4,
	bezier = "easeOutExpo",
})

-- Fades
hl.animation({
	leaf = "fade",
	enabled = true,
	speed = 2.0,
	bezier = "almostLinear",
})

hl.animation({
	leaf = "fadeIn",
	enabled = true,
	speed = 2.8,
	bezier = "almostLinear",
})

hl.animation({
	leaf = "fadeOut",
	enabled = true,
	speed = 1.8,
	bezier = "almostLinear",
})

hl.animation({
	leaf = "fadeSwitch",
	enabled = true,
	speed = 1.2,
	bezier = "almostLinear",
})

hl.animation({
	leaf = "fadeShadow",
	enabled = true,
	speed = 1.5,
	bezier = "easeOutQuint",
})

hl.animation({
	leaf = "fadeDim",
	enabled = true,
	speed = 2.0,
	bezier = "easeInOutCubic",
})

hl.animation({
	leaf = "fadePopups",
	enabled = true,
	speed = 1.8,
	bezier = "almostLinear",
})

hl.animation({
	leaf = "fadePopupsIn",
	enabled = true,
	speed = 1.8,
	bezier = "almostLinear",
})

hl.animation({
	leaf = "fadePopupsOut",
	enabled = true,
	speed = 1.2,
	bezier = "almostLinear",
})

hl.animation({
	leaf = "fadeDpms",
	enabled = true,
	speed = 6.0,
	bezier = "linear",
})

-- Layers
hl.animation({
	leaf = "layers",
	enabled = true,
	speed = 2.2,
	bezier = "easeOutExpo",
	style = "popin 96%",
})

hl.animation({
	leaf = "layersIn",
	enabled = true,
	speed = 2.2,
	bezier = "easeOutExpo",
	style = "popin 96%",
})

hl.animation({
	leaf = "layersOut",
	enabled = true,
	speed = 1.4,
	bezier = "easeInQuint",
	style = "popin 96%",
})

hl.animation({
	leaf = "fadeLayers",
	enabled = true,
	speed = 2.2,
	bezier = "almostLinear",
})

hl.animation({
	leaf = "fadeLayersIn",
	enabled = true,
	speed = 2.2,
	bezier = "almostLinear",
})

hl.animation({
	leaf = "fadeLayersOut",
	enabled = true,
	speed = 1.4,
	bezier = "almostLinear",
})

-- Workspaces
hl.animation({
	leaf = "workspaces",
	enabled = true,
	speed = 2.6,
	bezier = "easeOutExpo",
	style = "slidefade 15%",
})

hl.animation({
	leaf = "workspacesIn",
	enabled = true,
	speed = 2.6,
	bezier = "easeOutExpo",
	style = "slidefade 15%",
})

hl.animation({
	leaf = "workspacesOut",
	enabled = true,
	speed = 2.6,
	bezier = "easeOutExpo",
	style = "slidefade 15%",
})

-- Special Workspace
hl.animation({
	leaf = "specialWorkspace",
	enabled = true,
	speed = 2.4,
	bezier = "easeOutExpo",
	style = "slidevert",
})

hl.animation({
	leaf = "specialWorkspaceIn",
	enabled = true,
	speed = 2.4,
	bezier = "easeOutExpo",
	style = "slidevert",
})

hl.animation({
	leaf = "specialWorkspaceOut",
	enabled = true,
	speed = 2.4,
	bezier = "easeOutExpo",
	style = "slidevert",
})

-- Border
hl.animation({
	leaf = "border",
	enabled = true,
	speed = 2.0,
	bezier = "easeOutQuint",
})

hl.animation({
	leaf = "borderangle",
	enabled = true,
	speed = 60,
	bezier = "linear",
	style = "loop",
})

-- Misc
hl.animation({
	leaf = "zoomFactor",
	enabled = true,
	speed = 2.5,
	bezier = "easeInOutCubic",
})

hl.animation({
	leaf = "monitorAdded",
	enabled = true,
	speed = 2.5,
	bezier = "easeOutExpo",
})
