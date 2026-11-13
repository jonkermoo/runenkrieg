--!strict
-- The gun card's drawn art (src/client/AmmoHud; user 2026-11-12: art "we design ourselves", drawn outside Roblox and
-- imported, the game only placing and moving it; "match at least the shape/silhouette of the gun to ours"). Each gun has
-- one sheet: its body drawn from its own meshes as Armory.build scales them (a side view from the gun's right, the
-- muzzle to the right; ink outline, flat tones, wood grain; without the parts the card moves: bolt, rounds, cases,
-- clips, magazine) at `body` (x, y, width, height on the sheet), its edges in gun space `z` (left edge at z[2], the
-- butt; right at z[1], the muzzle) and `y` (bottom, top); `bolt`: the gun's own bolt drawn from its mesh, a frame per
-- step of its `turn` (degrees; one frame when it doesn't turn), every frame the same box in gun space (`z`, `y`, the
-- bolt closed); `round`: which drawn round it takes ("rifle", "pistol", "shell").
-- `parts`: the sheet shared by every gun: rounds, spent cases and their standing pips (`_pip`, `_pip_spent`), the
-- recesses cut into the gun (nine-sliced: `slice`, px on the sprite), a detachable box, an en-bloc clip's plate, a
-- stripper clip's strip, the revolver's cylinder from behind (drum, hub, hole, head); each `rect` on the sheet with
-- `bleed` px of outline round its content. `wash`: the brushed ink wash behind the gun, its brass rule under it.
-- To redraw them: tools/gunart (local tooling, README.md there).
export type Sprite = { rect: { number }, bleed: number, slice: { number }? }
export type Bolt = { frames: { { number } }, z: { number }, y: { number }, turn: number }
export type Gun = { image: number, body: { number }, z: { number }, y: { number }, round: string, bolt: Bolt? }

local GunArt: { wash: number, parts: { image: number, sprites: { [string]: Sprite } }, guns: { [string]: Gun } } = {
	wash = 80555168305590,
	parts = {
		image = 85479220272526,
		sprites = {
			rifle = { rect = { 0, 0, 216, 60 }, bleed = 8 },
			rifle_spent = { rect = { 220, 0, 216, 60 }, bleed = 8 },
			rifle_pip = { rect = { 440, 0, 30, 108 }, bleed = 4 },
			rifle_pip_spent = { rect = { 474, 0, 30, 108 }, bleed = 4 },
			pistol = { rect = { 508, 0, 146, 60 }, bleed = 8 },
			pistol_spent = { rect = { 658, 0, 146, 60 }, bleed = 8 },
			pistol_pip = { rect = { 808, 0, 30, 73 }, bleed = 4 },
			pistol_pip_spent = { rect = { 842, 0, 30, 73 }, bleed = 4 },
			shell = { rect = { 0, 112, 166, 72 }, bleed = 8 },
			shell_spent = { rect = { 170, 112, 166, 72 }, bleed = 8 },
			shell_pip = { rect = { 340, 112, 36, 83 }, bleed = 4 },
			shell_pip_spent = { rect = { 380, 112, 36, 83 }, bleed = 4 },
			recess = { rect = { 420, 112, 96, 96 }, bleed = 0, slice = { 32, 32, 64, 64 } },
			recess_open = { rect = { 520, 112, 96, 96 }, bleed = 0, slice = { 32, 32, 64, 64 } },
			box_open = { rect = { 620, 112, 96, 96 }, bleed = 0, slice = { 32, 32, 64, 64 } },
			plate = { rect = { 720, 112, 96, 96 }, bleed = 0, slice = { 32, 32, 64, 64 } },
			strip = { rect = { 820, 112, 30, 136 }, bleed = 8 },
			drum = { rect = { 0, 252, 384, 384 }, bleed = 0 },
			hub = { rect = { 388, 252, 64, 64 }, bleed = 0 },
			hole = { rect = { 456, 252, 96, 96 }, bleed = 0 },
			head = { rect = { 556, 252, 96, 96 }, bleed = 0 },
		},
	},
	guns = {
		pistol_c96 = {
			image = 116544325248268,
			body = { 0, 0, 886, 640 },
			z = { -1.5902, 0.5972 },
			y = { -1.0079, 0.5722 },
			round = "pistol",
			bolt = {
				frames = { { 0, 644, 384, 92 } },
				z = { -0.5957, 0.3535 },
				y = { 0.2472, 0.4743 },
				turn = 0,
			},
		},
		pistol_nagant = {
			image = 115379418012719,
			body = { 0, 0, 890, 640 },
			z = { -1.006, 0.7406 },
			y = { -0.8859, 0.37 },
			round = "pistol",
		},
		pistol_webley = {
			image = 79880904110797,
			body = { 0, 0, 911, 640 },
			z = { -1.3105, 0.7895 },
			y = { -0.913, 0.5626 },
			round = "pistol",
		},
		rifle_g98 = {
			image = 71728688119812,
			body = { 0, 0, 1024, 276 },
			z = { -3.9554, 1.5016 },
			y = { -1.1013, 0.3696 },
			round = "rifle",
			bolt = {
				frames = {
					{ 0, 280, 177, 105 },
					{ 181, 280, 177, 105 },
					{ 362, 280, 177, 105 },
					{ 543, 280, 177, 105 },
					{ 724, 280, 177, 105 },
				},
				z = { -0.7788, 0.1679 },
				y = { 0.035, 0.5945 },
				turn = 90,
			},
		},
		rifle_m91 = {
			image = 76475568701457,
			body = { 0, 0, 1024, 269 },
			z = { -4.0135, 1.5932 },
			y = { -1.1156, 0.3589 },
			round = "rifle",
			bolt = {
				frames = {
					{ 0, 273, 181, 132 },
					{ 185, 273, 181, 132 },
					{ 370, 273, 181, 132 },
					{ 555, 273, 181, 132 },
					{ 740, 273, 181, 132 },
				},
				z = { -0.7445, 0.2498 },
				y = { 0.0369, 0.7581 },
				turn = 90,
			},
		},
		rifle_mondragon = {
			image = 132094180790546,
			body = { 0, 0, 1024, 295 },
			z = { -3.4006, 1.4342 },
			y = { -0.9965, 0.3976 },
			round = "rifle",
			bolt = {
				frames = { { 0, 299, 126, 42 } },
				z = { -0.6295, -0.0357 },
				y = { 0.0628, 0.2622 },
				turn = 0,
			},
		},
		rifle_remington8 = {
			image = 75442212463471,
			body = { 0, 0, 1024, 315 },
			z = { -2.9702, 1.6196 },
			y = { -1.0243, 0.3895 },
			round = "rifle",
			bolt = {
				frames = { { 0, 319, 85, 47 } },
				z = { -0.4949, -0.115 },
				y = { 0.06, 0.2733 },
				turn = 0,
			},
		},
		rifle_smle = {
			image = 88544745160083,
			body = { 0, 0, 1024, 308 },
			z = { -3.4538, 1.4905 },
			y = { -1.038, 0.4482 },
			round = "rifle",
			bolt = {
				frames = {
					{ 0, 312, 176, 114 },
					{ 180, 312, 176, 114 },
					{ 360, 312, 176, 114 },
					{ 540, 312, 176, 114 },
					{ 720, 312, 176, 114 },
				},
				z = { -0.6236, 0.2282 },
				y = { -0.1685, 0.3841 },
				turn = 60,
			},
		},
		rifle_winchester1907 = {
			image = 82288093267355,
			body = { 0, 0, 1024, 349 },
			z = { -2.7292, 1.7244 },
			y = { -1.1823, 0.3355 },
			round = "rifle",
			bolt = {
				frames = { { 0, 353, 451, 85 } },
				z = { -2.0053, -0.0429 },
				y = { -0.1124, 0.2578 },
				turn = 0,
			},
		},
		shotgun_m1897 = {
			image = 94335911196623,
			body = { 0, 0, 1024, 316 },
			z = { -2.8066, 1.5663 },
			y = { -1.0243, 0.3278 },
			round = "shell",
			bolt = {
				frames = { { 0, 320, 111, 37 } },
				z = { -0.5652, -0.0903 },
				y = { 0.1093, 0.2683 },
				turn = 0,
			},
		},
	},
}

return table.freeze(GunArt)
