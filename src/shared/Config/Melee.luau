--!strict
-- A gun's melee: the butt stroke (user 2026-10-22: "work on adding a melee feature on guns"; the design approved the
-- same day). Every gun with ammo (Config/Weapons `ammo`): the melee key (Settings Key_Melee, V) drives the butt forward
-- and up into whoever stands in front, then back to the hold. src/client/Melee (the key, the animations, the sounds),
-- src/server/Melee (the hit check), Rules/Melee; the damage and knocks are Config/Damage.Melee. Data only.

local Melee = {
	-- one strike (seconds): `impact` after the key the butt lands (the client sends the hit then, the server casts it);
	-- the animation is back in the hold at `length`; the next strike from `cooldown`
	Strike = { impact = 0.25, length = 0.75, cooldown = 0.9 },

	-- the hit check on the server (src/server/Melee): a box `reach` studs long (~2 m: arm and rifle) and 2 x `radius`
	-- across, out from the striker's head along the strike's direction; the direction must be within `cone` degrees of
	-- where the soldier faces (flat), and the strike within `slack` seconds of the cooldown (latency)
	Hit = { reach = 5.5, radius = 1.2, cone = 35, slack = 0.15 },

	-- the swing and the hit, heard by everyone (Config/Audio profile `Mechanism`); ids 0: not picked yet
	Sounds = {
		Swing = { id = 0, volume = 0.8, profile = "Mechanism" },
		Body = { id = 0, volume = 1.2, profile = "Mechanism" }, -- the butt on a soldier
		Helmet = { id = 0, volume = 1.2, profile = "Mechanism" }, -- on a helmet (it comes off)
		Surface = { id = 0, volume = 1, profile = "Mechanism" }, -- on a wall, a tree, the ground
	},
}

return table.freeze(Melee)
