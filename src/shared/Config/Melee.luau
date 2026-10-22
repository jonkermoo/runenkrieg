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

	-- the swing, heard by everyone (Config/Audio profile `Mechanism`): "Wood Whoosh Slicing Air Quick Swings 1"
	-- (ProSoundEffects; user 2026-10-22: "just a swinging sound is good", no hit sounds). The striker hears it `delay`
	-- seconds after the key (as the butt comes forward), everyone else when the server has the strike ("Struck")
	Swing = { id = 9120972444, volume = 0.8, profile = "Mechanism", delay = 0.1 },
}

return table.freeze(Melee)
