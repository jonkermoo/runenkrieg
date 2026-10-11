--!strict
-- Soldier uniforms (uniform1 = slate/grey team, uniform2 = olive team): Shirt + Pants templates painted by
-- tools/clothing/uniform.py from assets/characters/uniforms/<name>.json, uploaded with Open Cloud. Ids here are IMAGE ids (resolved
-- from the uploaded Decal in Studio, see docs/KNOWN_TRAPS.md); decal ids are kept for reference.
-- Skin shows through the transparent hands and the head; 3D gear (helmet, belt, pouches) goes on top.

local Uniforms = {
	Default = "uniform1", -- until nations are decided, everyone wears this
	-- Every soldier's face (docs/CHARACTERS.md Faces): the user's eye traced and drawn at 1024x1024, whites rounded on
	-- the nose side, fitted inside the head's flat front (tools/face/trace.py -> assets/characters/faces/
	-- face_hq_round.png). Image id (decal 112836590873970).
	Face = 70938855237782,
	Kits = {
		uniform1 = {
			source = "assets/characters/uniforms/uniform1.json",
			shirt = 111439602118520, -- decal 121662410098818
			pants = 82001103410866, -- decal 121600662647379
			skin = { 226, 176, 104 },
			headwear = "helmet_stahl", -- Config/Assets entry
		},
		uniform2 = {
			source = "assets/characters/uniforms/uniform2.json",
			shirt = 108022442236637, -- decal 118417766232661
			pants = 78199869429201, -- decal 112322397513846
			skin = { 226, 176, 104 },
			headwear = "helmet_m33", -- Config/Assets entry
			weapon = "rifle_m91", -- Config/Weapons entry: the olive team's default rifle
		},
	},
}

return Uniforms
