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
	Kits = {
		uniform1 = {
			source = "assets/teams/grey/uniform/uniform1.json",
			shirt = 111439602118520, -- decal 121662410098818
			pants = 82001103410866, -- decal 121600662647379
			skin = { 226, 176, 104 },
			headwear = "helmet_stahl", -- Config/Assets entry
		},
		uniform2 = {
			source = "assets/teams/olive/uniform/uniform2.json",
			shirt = 108022442236637, -- decal 118417766232661
			pants = 78199869429201, -- decal 112322397513846
			skin = { 226, 176, 104 },
			headwear = "helmet_m33", -- Config/Assets entry
			weapon = "rifle_m91", -- Config/Weapons entry: the olive team's default rifle
		},
	},
}

return Uniforms
