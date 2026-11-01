--!strict
-- The shape of each tree kit canopy's leaves (Config/Assets.Entries.TreeKit), for where a bullet's line really enters
-- the leaves (src/client/Impacts: the falling leaves; user 2026-11-01: shots beside the leaves burst them, from the
-- canopy's box corners). Each canopy is the pieces tools/blender/trees.py built it from, measured off the uploaded
-- FBX by tools/blender/tree_hitshapes.py: pines are stacked cones, broadleaf and birch squashed spheres (its axes
-- checked in Studio against each canopy's precise collision: 94-97% of lines through the box agree).
-- Units: shares of the canopy part's half size, from its centre, in its own axes (so any tree scale fits).
-- Cone: base centre (x, y, z), base radii (rx, rz), apex `height` above the base. Ellipsoid: centre, radii.
-- A canopy is told apart by its Size's proportions (`size`: the mesh's box; only the ratios count).

local TreeShapes = {
	-- the closest variant's `size` proportions must be within this (each axis / Y) to use its shapes
	matchTolerance = 0.03,
	-- every piece grown by this about its own centre (1 = as measured)
	grow = 1,
	-- a canopy matching no variant: one ellipsoid filling its box
	Fallback = { { shape = "Ellipsoid", x = 0, y = 0, z = 0, rx = 1, ry = 1, rz = 1 } },

	Variants = {
		BirchA = {
			size = { 0.141, 0.225, 0.126 },
			shapes = {
				{ shape = "Ellipsoid", x = -0.279, y = -0.368, z = 0.190, rx = 0.721, ry = 0.632, rz = 0.810 },
				{ shape = "Ellipsoid", x = 0.254, y = 0.048, z = -0.245, rx = 0.746, ry = 0.592, rz = 0.755 },
				{ shape = "Ellipsoid", x = -0.263, y = 0.457, z = -0.274, rx = 0.674, ry = 0.543, rz = 0.687 },
			},
		},
		BirchB = {
			size = { 0.118, 0.208, 0.122 },
			shapes = {
				{ shape = "Ellipsoid", x = -0.110, y = -0.403, z = 0.203, rx = 0.845, ry = 0.597, rz = 0.772 },
				{ shape = "Ellipsoid", x = 0.118, y = 0.001, z = 0.088, rx = 0.882, ry = 0.630, rz = 0.912 },
				{ shape = "Ellipsoid", x = -0.118, y = 0.430, z = -0.221, rx = 0.882, ry = 0.570, rz = 0.779 },
			},
		},
		BroadleafA = {
			size = { 0.238, 0.161, 0.197 },
			shapes = {
				{ shape = "Ellipsoid", x = 0.039, y = 0.043, z = 0.000, rx = 0.842, ry = 0.957, rz = 1.000 },
				{ shape = "Ellipsoid", x = -0.418, y = -0.217, z = 0.234, rx = 0.582, ry = 0.783, rz = 0.760 },
				{ shape = "Ellipsoid", x = 0.453, y = -0.037, z = 0.099, rx = 0.547, ry = 0.671, rz = 0.635 },
			},
		},
		BroadleafB = {
			size = { 0.247, 0.160, 0.214 },
			shapes = {
				{ shape = "Ellipsoid", x = 0.026, y = 0.044, z = -0.045, rx = 0.773, ry = 0.956, rz = 0.955 },
				{ shape = "Ellipsoid", x = 0.437, y = -0.255, z = 0.208, rx = 0.563, ry = 0.745, rz = 0.593 },
				{ shape = "Ellipsoid", x = -0.427, y = -0.170, z = 0.337, rx = 0.573, ry = 0.721, rz = 0.663 },
			},
		},
		BroadleafC = {
			size = { 0.218, 0.171, 0.226 },
			shapes = {
				{ shape = "Ellipsoid", x = -0.025, y = 0.060, z = 0.128, rx = 0.975, ry = 0.940, rz = 0.872 },
				{ shape = "Ellipsoid", x = -0.162, y = -0.303, z = -0.385, rx = 0.603, ry = 0.697, rz = 0.615 },
				{ shape = "Ellipsoid", x = 0.430, y = -0.284, z = 0.004, rx = 0.570, ry = 0.613, rz = 0.534 },
			},
		},
		PineA = {
			size = { 0.199, 0.397, 0.199 },
			shapes = {
				{ shape = "Cone", x = 0.021, y = -1.000, z = 0.016, rx = 1.021, rz = 1.016, height = 0.628 },
				{ shape = "Cone", x = 0.044, y = -0.572, z = 0.033, rx = 0.836, rz = 0.847, height = 0.665 },
				{ shape = "Cone", x = 0.042, y = -0.133, z = 0.037, rx = 0.626, rz = 0.592, height = 0.693 },
				{ shape = "Cone", x = 0.048, y = 0.306, z = 0.031, rx = 0.440, rz = 0.421, height = 0.694 },
			},
		},
		PineB = {
			size = { 0.203, 0.388, 0.214 },
			shapes = {
				{ shape = "Cone", x = 0.015, y = -1.000, z = -0.028, rx = 1.015, rz = 1.028, height = 0.681 },
				{ shape = "Cone", x = 0.027, y = -0.551, z = -0.049, rx = 0.847, rz = 0.673, height = 0.624 },
				{ shape = "Cone", x = 0.035, y = -0.103, z = -0.031, rx = 0.610, rz = 0.605, height = 0.679 },
				{ shape = "Cone", x = 0.018, y = 0.346, z = -0.043, rx = 0.395, rz = 0.322, height = 0.654 },
			},
		},
		PineC = {
			size = { 0.203, 0.388, 0.200 },
			shapes = {
				{ shape = "Cone", x = 0.031, y = -1.000, z = 0.009, rx = 1.031, rz = 1.009, height = 0.622 },
				{ shape = "Cone", x = -0.009, y = -0.546, z = -0.005, rx = 0.798, rz = 0.799, height = 0.664 },
				{ shape = "Cone", x = 0.026, y = -0.105, z = 0.002, rx = 0.617, rz = 0.679, height = 0.613 },
				{ shape = "Cone", x = 0.023, y = 0.345, z = -0.014, rx = 0.444, rz = 0.415, height = 0.655 },
			},
		},
	},
}

return TreeShapes
