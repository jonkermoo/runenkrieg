--!strict
-- Soldier uniforms: Shirt + Pants templates painted by tools/clothing/uniform.py from
-- assets/characters/uniforms/<name>.json, uploaded with Open Cloud. Ids here are IMAGE ids (resolved
-- from the uploaded Decal in Studio, see docs/KNOWN_TRAPS.md); decal ids are kept for reference.
-- Skin shows through the transparent hands and the head; 3D gear (helmet, belt, pouches) goes on top.

local Uniforms = {
	Default = "SlateTunic", -- until nations are decided, everyone wears this
	Kits = {
		SlateTunic = {
			source = "assets/characters/uniforms/slate_tunic.json",
			shirt = 111439602118520, -- decal 121662410098818
			pants = 82001103410866, -- decal 121600662647379
			skin = { 226, 176, 104 },
			headwear = "HelmetStahl", -- Config/Assets entry
		},
		OliveField = {
			source = "assets/characters/uniforms/olive_field.json",
			shirt = 108022442236637, -- decal 118417766232661
			pants = 78199869429201, -- decal 112322397513846
			skin = { 226, 176, 104 },
			headwear = "HelmetM33", -- Config/Assets entry
		},
	},
}

return Uniforms
