--!strict
-- Client-side tree sway and explosion response. Angles in degrees. Rules/TreeSway does the math,
-- src/client/TreeSway animates. Visual only: the server never moves trees, so hit detection uses
-- the static pose (max visual offset ~0.4 studs at the canopy edge).

local TreeSway = {
	Tag = "SwayTree", -- CollectionService tag on tree Models (set by the map builder)
	ActiveRadius = 180, -- only trees this close to the camera are animated
	GridCell = 64,
	UpdateHz = 40,

	-- Wind follows workspace.GlobalWind (shared with grass/particles). Strength 1 at this speed.
	WindReference = 12,
	DefaultWind = { x = 10, z = 4 }, -- used when GlobalWind is zero; the builder also sets GlobalWind

	Gust = {
		slowFreq = 0.35, -- Hz, main sway
		fastFreq = 1.05, -- Hz, flutter layered on top
		waveLength = 140, -- studs: gusts roll across the forest downwind
		cross = 0.3, -- sideways wobble relative to the main sway
		lean = 0.45, -- constant downwind lean, as a fraction of amplitude
	},

	-- Wood barely moves; leaves move more. Springs drive the explosion response.
	Trunk = { amp = 0.25, stiffness = 140, damping = 10, maxLean = 6, impulseScale = 1 },
	Canopy = { amp = 1.4, stiffness = 55, damping = 4.5, maxLean = 18, impulseScale = 3 },

	Explosion = {
		maxKick = 90, -- deg/s angular velocity given to a trunk at the blast center (canopy x impulseScale)
	},

	SleepAngle = 0.01, -- deg: springs below this (and nearly still) stop being simulated
}

return table.freeze(TreeSway)
