--!strict
-- The staff's and the artillery's drawn art (src/client/StaffHud, src/client/ArtilleryHud, src/client/HudKit.gemArt; user
-- 2026-11-12: art "we design ourselves", drawn outside Roblox from the game's own meshes and imported, the game only
-- placing, tinting and moving it; "the brass ring and cutaway drawing looks best, but still make it accurate to our
-- actual model asset"). Rects are x, y, width, height on their sheet; `z` / `y` a drawing's edges in its model's own
-- space (studs: the left edge at z[2], the right at z[1], bottom and top), seen from the model's right (+X).
-- `gem`: one sheet, the brass ring, the crystal (Config/Assets hud_gem's Crystal and its cracks seen from behind, in
-- tones of white: the game tints it) `crystalSize` studs across and tall, and its shards (`size` studs, `at` where each
-- floats about the crystal's middle).
-- `guns` by asset: the field gun in each paint (Config/Palette.Artillery.Paint): `still` the carriage, wheels and mount
-- (one image); `parts` a sheet with the cradle, the barrel (its chamber cut away), the breech block's swing in `frames`
-- (shut to open, one box), the round and its fired case (about the case's head, the nose toward -Z). The machine gun
-- (mg08) the same way: `still` its tripod, mount and ammo can, the cradle and barrel, and `belt`: each round on the
-- belt (case, bullet and link; Rounds01 first) where it hangs at rest.
-- To redraw them: tools/gunart (local tooling, README.md there).
export type Piece = { rect: { number }, z: { number }, y: { number } }
export type Scheme = {
	still: { image: number, z: { number }, y: { number } },
	parts: number,
	barrel: Piece,
	cradle: Piece,
	breech: { frames: { { number } }, z: { number }, y: { number } }?,
	round: Piece?,
	case: Piece?,
	belt: { Piece }?,
}
export type Shard = { rect: { number }, size: { number }, at: { number } }

local HudArt: {
	gem: { image: number, ring: { number }, crystal: { number }, crystalSize: { number }, shards: { Shard } },
	round: { length: number, width: number }, -- the field gun's round (studs)
	guns: { [string]: { [string]: Scheme } },
} =
	{
		gem = {
			image = 125446492035113,
			ring = { 0, 0, 480, 480 },
			crystal = { 484, 0, 321, 400 },
			crystalSize = { 1.626, 2.028 },
			shards = {
				{ rect = { 809, 0, 76, 106 }, size = { 0.385, 0.536 }, at = { -1.092, 0.332, 0.121 } },
				{ rect = { 889, 0, 55, 70 }, size = { 0.282, 0.355 }, at = { -0.169, -0.442, 1.159 } },
				{ rect = { 948, 0, 67, 91 }, size = { 0.342, 0.461 }, at = { 0.916, 0.06, 0.572 } },
				{ rect = { 0, 484, 56, 52 }, size = { 0.287, 0.264 }, at = { 0.716, 0.471, -0.708 } },
				{ rect = { 60, 484, 56, 88 }, size = { 0.284, 0.446 }, at = { -0.384, -0.2, -1.11 } },
			},
		},
		round = { length = 1.569, width = 0.282 },
		guns = {
			artillery_qf18 = {
				Grey = {
					still = { image = 128218233738305, z = { -1.894, 7.65 }, y = { -0.35, 3.94 } },
					parts = 91649061457015,
					barrel = { rect = { 0, 0, 933, 122 }, z = { -3.81, 2.41 }, y = { 2.494, 3.31 } },
					cradle = { rect = { 0, 126, 831, 99 }, z = { -3.48, 2.06 }, y = { 2.18, 2.84 } },
					breech = {
						frames = {
							{ 835, 126, 102, 76 },
							{ 0, 229, 102, 76 },
							{ 106, 229, 102, 76 },
							{ 212, 229, 102, 76 },
							{ 318, 229, 102, 76 },
						},
						z = { 2.2026, 2.885 },
						y = { 2.657, 3.163 },
					},
					round = { rect = { 424, 229, 250, 57 }, z = { -1.619, 0.05 }, y = { -0.191, 0.191 } },
					case = { rect = { 678, 229, 250, 57 }, z = { -1.619, 0.05 }, y = { -0.191, 0.191 } },
				},
				Olive = {
					still = { image = 91575612484474, z = { -1.894, 7.65 }, y = { -0.35, 3.94 } },
					parts = 81870713791592,
					barrel = { rect = { 0, 0, 933, 122 }, z = { -3.81, 2.41 }, y = { 2.494, 3.31 } },
					cradle = { rect = { 0, 126, 831, 99 }, z = { -3.48, 2.06 }, y = { 2.18, 2.84 } },
					breech = {
						frames = {
							{ 835, 126, 102, 76 },
							{ 0, 229, 102, 76 },
							{ 106, 229, 102, 76 },
							{ 212, 229, 102, 76 },
							{ 318, 229, 102, 76 },
						},
						z = { 2.2026, 2.885 },
						y = { 2.657, 3.163 },
					},
					round = { rect = { 424, 229, 250, 57 }, z = { -1.619, 0.05 }, y = { -0.191, 0.191 } },
					case = { rect = { 678, 229, 250, 57 }, z = { -1.619, 0.05 }, y = { -0.191, 0.191 } },
				},
				Brown = {
					still = { image = 78406295022575, z = { -1.894, 7.65 }, y = { -0.35, 3.94 } },
					parts = 129095853517793,
					barrel = { rect = { 0, 0, 933, 122 }, z = { -3.81, 2.41 }, y = { 2.494, 3.31 } },
					cradle = { rect = { 0, 126, 831, 99 }, z = { -3.48, 2.06 }, y = { 2.18, 2.84 } },
					breech = {
						frames = {
							{ 835, 126, 102, 76 },
							{ 0, 229, 102, 76 },
							{ 106, 229, 102, 76 },
							{ 212, 229, 102, 76 },
							{ 318, 229, 102, 76 },
						},
						z = { 2.2026, 2.885 },
						y = { 2.657, 3.163 },
					},
					round = { rect = { 424, 229, 250, 57 }, z = { -1.619, 0.05 }, y = { -0.191, 0.191 } },
					case = { rect = { 678, 229, 250, 57 }, z = { -1.619, 0.05 }, y = { -0.191, 0.191 } },
				},
			},
			mg08 = {
				Grey = {
					still = { image = 112443539287396, z = { -0.77, 1.622 }, y = { -1.16, 1.165 } },
					parts = 119038825644000,
					barrel = { rect = { 0, 0, 631, 81 }, z = { -4.286, -0.077 }, y = { 0.978, 1.522 } },
					cradle = { rect = { 0, 85, 470, 210 }, z = { -0.207, 2.928 }, y = { 0.425, 1.827 } },
					belt = {
						{ rect = { 474, 85, 97, 40 }, z = { 0.05, 0.701 }, y = { 1.251, 1.522 } },
						{ rect = { 575, 85, 97, 41 }, z = { 0.04, 0.691 }, y = { 1.226, 1.498 } },
						{ rect = { 676, 85, 97, 40 }, z = { 0.017, 0.668 }, y = { 1.127, 1.398 } },
						{ rect = { 777, 85, 97, 41 }, z = { 0.026, 0.677 }, y = { 1.029, 1.301 } },
						{ rect = { 878, 85, 97, 41 }, z = { 0.042, 0.693 }, y = { 0.934, 1.206 } },
						{ rect = { 0, 299, 97, 41 }, z = { 0.062, 0.713 }, y = { 0.84, 1.112 } },
						{ rect = { 101, 299, 97, 40 }, z = { 0.083, 0.734 }, y = { 0.743, 1.014 } },
						{ rect = { 202, 299, 97, 41 }, z = { 0.106, 0.756 }, y = { 0.637, 0.909 } },
						{ rect = { 303, 299, 97, 40 }, z = { 0.132, 0.783 }, y = { 0.516, 0.787 } },
						{ rect = { 404, 299, 97, 41 }, z = { 0.162, 0.813 }, y = { 0.369, 0.641 } },
						{ rect = { 505, 299, 97, 40 }, z = { 0.174, 0.825 }, y = { 0.218, 0.489 } },
						{ rect = { 606, 299, 97, 41 }, z = { 0.175, 0.825 }, y = { 0.065, 0.337 } },
					},
				},
				Olive = {
					still = { image = 109084465779433, z = { -0.77, 1.622 }, y = { -1.16, 1.165 } },
					parts = 119038825644000,
					barrel = { rect = { 0, 0, 631, 81 }, z = { -4.286, -0.077 }, y = { 0.978, 1.522 } },
					cradle = { rect = { 0, 85, 470, 210 }, z = { -0.207, 2.928 }, y = { 0.425, 1.827 } },
					belt = {
						{ rect = { 474, 85, 97, 40 }, z = { 0.05, 0.701 }, y = { 1.251, 1.522 } },
						{ rect = { 575, 85, 97, 41 }, z = { 0.04, 0.691 }, y = { 1.226, 1.498 } },
						{ rect = { 676, 85, 97, 40 }, z = { 0.017, 0.668 }, y = { 1.127, 1.398 } },
						{ rect = { 777, 85, 97, 41 }, z = { 0.026, 0.677 }, y = { 1.029, 1.301 } },
						{ rect = { 878, 85, 97, 41 }, z = { 0.042, 0.693 }, y = { 0.934, 1.206 } },
						{ rect = { 0, 299, 97, 41 }, z = { 0.062, 0.713 }, y = { 0.84, 1.112 } },
						{ rect = { 101, 299, 97, 40 }, z = { 0.083, 0.734 }, y = { 0.743, 1.014 } },
						{ rect = { 202, 299, 97, 41 }, z = { 0.106, 0.756 }, y = { 0.637, 0.909 } },
						{ rect = { 303, 299, 97, 40 }, z = { 0.132, 0.783 }, y = { 0.516, 0.787 } },
						{ rect = { 404, 299, 97, 41 }, z = { 0.162, 0.813 }, y = { 0.369, 0.641 } },
						{ rect = { 505, 299, 97, 40 }, z = { 0.174, 0.825 }, y = { 0.218, 0.489 } },
						{ rect = { 606, 299, 97, 41 }, z = { 0.175, 0.825 }, y = { 0.065, 0.337 } },
					},
				},
				Brown = {
					still = { image = 100665391590861, z = { -0.77, 1.622 }, y = { -1.16, 1.165 } },
					parts = 119038825644000,
					barrel = { rect = { 0, 0, 631, 81 }, z = { -4.286, -0.077 }, y = { 0.978, 1.522 } },
					cradle = { rect = { 0, 85, 470, 210 }, z = { -0.207, 2.928 }, y = { 0.425, 1.827 } },
					belt = {
						{ rect = { 474, 85, 97, 40 }, z = { 0.05, 0.701 }, y = { 1.251, 1.522 } },
						{ rect = { 575, 85, 97, 41 }, z = { 0.04, 0.691 }, y = { 1.226, 1.498 } },
						{ rect = { 676, 85, 97, 40 }, z = { 0.017, 0.668 }, y = { 1.127, 1.398 } },
						{ rect = { 777, 85, 97, 41 }, z = { 0.026, 0.677 }, y = { 1.029, 1.301 } },
						{ rect = { 878, 85, 97, 41 }, z = { 0.042, 0.693 }, y = { 0.934, 1.206 } },
						{ rect = { 0, 299, 97, 41 }, z = { 0.062, 0.713 }, y = { 0.84, 1.112 } },
						{ rect = { 101, 299, 97, 40 }, z = { 0.083, 0.734 }, y = { 0.743, 1.014 } },
						{ rect = { 202, 299, 97, 41 }, z = { 0.106, 0.756 }, y = { 0.637, 0.909 } },
						{ rect = { 303, 299, 97, 40 }, z = { 0.132, 0.783 }, y = { 0.516, 0.787 } },
						{ rect = { 404, 299, 97, 41 }, z = { 0.162, 0.813 }, y = { 0.369, 0.641 } },
						{ rect = { 505, 299, 97, 40 }, z = { 0.174, 0.825 }, y = { 0.218, 0.489 } },
						{ rect = { 606, 299, 97, 41 }, z = { 0.175, 0.825 }, y = { 0.065, 0.337 } },
					},
				},
			},
		},
	}

return table.freeze(HudArt)
