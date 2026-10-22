--!strict
-- The short screen blur when a bullet passes close or something blows up nearby (src/client/ScreenBlur,
-- Rules/ScreenBlur; user 2026-10-22: "add blurring when bullets come near you / explosion near you"). Strengths are
-- shares of `MaxSize`; a new hit over a blur already showing takes the stronger one plus `Stack` of the weaker, never
-- past `Cap`, so a barrage never blinds. Turned off with the "ScreenBlur" setting. Data only.

local ScreenBlur = {
	MaxSize = 20, -- BlurEffect.Size at strength 1 (Roblox's largest is 56)
	Cap = 1, -- the most strength hits can build up to
	Stack = 0.3, -- share of the weaker hit added over the stronger

	-- a bullet passing within Config/Audio.Heard.pass.radius (15 studs) of the camera: `peak` on its path, nothing at
	-- the radius, `curve` the falloff's steepness (1 = straight)
	Pass = { peak = 0.45, curve = 1.5 },

	-- an explosion (src/client/Vfx/Blast, every blast: grenades, staff stages, shells, dev blasts) with a fireball
	-- `fireball` studs across (a Mills ~5, a 2.5 kg shell ~15, the 50 kg bomb ~38, staff stages 4 / 9 / 22): felt out to
	-- `reach` x the fireball (at most `maxReach` studs), as strong as the fireball's share of `full` (at least `least`)
	Blast = { reach = 8, maxReach = 220, full = 20, least = 0.5, curve = 1.5 },

	-- the shape over time (seconds): eases in over about `rise`, holds `hold`, eases out over about `fall`; gone below
	-- `floor`
	Rise = 0.05,
	Hold = 0.1,
	Fall = 0.4,
	Floor = 0.01,
}

return table.freeze(ScreenBlur)
