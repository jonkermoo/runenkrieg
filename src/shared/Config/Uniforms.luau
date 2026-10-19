--!strict
-- Soldier uniforms (uniform1 = slate/grey team, uniform2 = olive team): Shirt + Pants templates painted by
-- tools/clothing/uniform.py from assets/teams/<team>/uniform/<name>.json, uploaded with Open Cloud. Ids here are IMAGE ids (resolved
-- from the uploaded Decal in Studio, see docs/KNOWN_TRAPS.md); decal ids are kept for reference.
-- Skin shows through the transparent hands and the head; 3D gear (helmet, belt, pouches) goes on top.

local Uniforms = {
	Default = "uniform1", -- until nations are decided, everyone wears this
	-- Every soldier's face, one per health third (docs/CHARACTERS.md Faces, user 2026-10-11): two dark brown dot
	-- eyes; two minor cuts and a light bruise in the middle third; a bigger cheek cut, a gnarly cut across the shut
	-- right eye and a darker bruise in the bottom third (realistic injuries, simple cartoon look). Each has its
	-- closed version (blinks, death) with the same injuries. tools/face/dots.py -> assets/characters/faces/face_dots*.png.
	-- Image ids (decals in docs/CHARACTERS.md). `above`: the face shows while Health / MaxHealth > above.
	-- !! DEATH: a killed character shows the CLOSED face of the tier it was in last (healthy -> 0 in one hit: the
	-- !! healthy closed face). Never pick the death face from health 0 (that would always be the wounded one).
	Faces = {
		{ name = "healthy", above = 2 / 3, open = 90297093549919, closed = 119896130854019 },
		{ name = "hurt", above = 1 / 3, open = 107066972986655, closed = 112253898229941 },
		{ name = "wounded", above = 0, open = 101504668403462, closed = 118275055282013 },
	},
	-- Blinking (src/client/Blink): every living character in range shuts its eyes (its tier's closed face) for
	-- `Closed` seconds, every MinGap..MaxGap seconds, each on its own random rhythm. Local only, nothing replicates.
	Blink = { MinGap = 2, MaxGap = 6, Closed = 0.12, Range = 80 },
	-- Looks rolled each life (user 2026-10-14: "a set rotation of colors ... for hair and a separate one for skin. these
	-- will rotate randomly per spawn"; docs/HAIRS.md): src/server/Bodies picks one skin and one hair color per spawn
	-- (Rules/Looks: by weight, never the same as the soldier's last life). The skin colors the whole body (the kit's
	-- `skin` is only the showcase dummies'); the hair color goes on the character as the "HairColor" attribute for the
	-- hair model. Hair: four natural colors equally likely, white the rare one (user 2026-10-14; 1 of 15).
	-- darker and warmer than the first set (user 2026-10-14: the first pale washed out to white in the bright light)
	Skins = {
		{ name = "pale", color = { 232, 186, 146 }, weight = 1 },
		{ name = "light", color = { 214, 158, 108 }, weight = 1 },
		{ name = "olive", color = { 184, 130, 82 }, weight = 1 },
		{ name = "brown", color = { 120, 78, 50 }, weight = 1 }, -- darkest: the dark brown dot eyes must still read
	},
	HairColors = {
		{ name = "black", color = { 34, 28, 26 }, weight = 3.5 },
		{ name = "brown", color = { 104, 70, 46 }, weight = 3.5 }, -- the helmet previews' hair (src/dev/HairPreview)
		{ name = "blonde", color = { 214, 182, 120 }, weight = 3.5 },
		{ name = "ginger", color = { 182, 92, 46 }, weight = 3.5 },
		{ name = "white", color = { 232, 228, 220 }, weight = 1 }, -- rare
	},
	-- The hairstyle, rolled each life like the colors (user 2026-10-14, bald included): Config/Assets `hair_<name>`
	-- (bareheaded) and `hair_<name>_<shell>` (under that helmet shell). Bald: no hair, only the helmet.
	Hairs = {
		{ name = "wolf_cut", weight = 1 },
		{ name = "low_ponytail", weight = 1 },
		{ name = "m_wolf", weight = 1 },
		{ name = "m_slick", weight = 1 },
		{ name = "m_midpart", weight = 1 },
		{ name = "bald", weight = 1 },
	},
	-- Helmets shot off (user 2026-10-14; docs/HATS.md): a hit in the top half of the head's hitbox (2 x 1 x 1, the R6
	-- Head part) knocks the worn helmet off; the helmet-on hair is swapped for the original and a loose copy of the
	-- helmet flies off along the shot (`speed` studs/s, plus `up`), tumbling (`spin` rad/s at most), and is gone after
	-- `despawn` seconds.
	HelmetOff = { speed = 18, up = 14, spin = 12, despawn = 10 },
	Kits = {
		uniform1 = {
			source = "assets/teams/grey/uniform/uniform1.json",
			shirt = 111439602118520, -- decal 121662410098818
			pants = 82001103410866, -- decal 121600662647379
			skin = { 226, 176, 104 },
			headwear = "helmet_stahl", -- Config/Assets entry
			pack = "pack_tornister", -- Config/Assets entry, worn on the back (src/server/Packs)
			weapon = "rifle_g98", -- Config/Weapons entry: the grey team's default rifle
			grenade = "grenade_stick", -- its grenades (Config/Grenades): the Stielhandgranate
		},
		uniform2 = {
			source = "assets/teams/olive/uniform/uniform2.json",
			shirt = 108022442236637, -- decal 118417766232661
			pants = 78199869429201, -- decal 112322397513846
			skin = { 226, 176, 104 },
			headwear = "helmet_m33", -- Config/Assets entry
			pack = "pack_zaino", -- Config/Assets entry, worn on the back (src/server/Packs)
			weapon = "rifle_m91", -- Config/Weapons entry: the olive team's default rifle
			grenade = "grenade_sipe", -- its grenades (Config/Grenades): the SIPE
		},
	},
}

return Uniforms
