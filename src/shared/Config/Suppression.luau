--!strict
-- Suppression (src/client/Suppression, Rules/Suppression; user 2026-11-01: "camera shake and arm wobble when shot near
-- or explosions go off (to make cover fire more useful)"). Enemy bullets passing close or landing close, and any
-- explosion nearby (your own and teammates' too), build a level from 0 to 1 on your own client. It holds `Hold` s after
-- the last hit, then falls by 1 every `Fall` s. While it is up, the first-person gun and arms wander (src/client/Sway)
-- and the camera shakes. Shots leave the visible gun's barrel, so the wander moves the aim: no extra spread. Third
-- person keeps its animations; only the view shakes. Client only, nothing sent. Data only.

return table.freeze({
	-- an enemy bullet passing within `radius` studs of your head: `add` on its path, nothing at the radius, `curve` the
	-- falloff's steepness (1 = straight); not within `clear` studs of the muzzle. A shotgun counts its nearest pellet.
	Pass = { radius = 6, add = 0.35, curve = 1.5, clear = 2 },
	-- an enemy bullet ending within `radius` studs of your head (each bullet counts the stronger of its pass and this)
	Impact = { radius = 5, add = 0.25, curve = 1.5 },
	-- an explosion of `kg` of TNT: `add` at the blast, nothing `reach` x the charge's cube root studs away (at most
	-- `maxReach`), `curve` the falloff. A Mills (71 g) reaches ~35 studs: ~0.8 at 5, ~0.2 at 20; a 2.5 kg shell ~115.
	Blast = { add = 1.1, reach = 85, maxReach = 250, curve = 2 },

	Cap = 1,
	Hold = 0.4,
	Fall = 1.5,
	-- the shake's size is level^grow, eased in at `ease` per second (so a hit never snaps the view)
	grow = 1.3,
	ease = 10,

	-- at full suppression (degrees): a slow wander `rate` times a second plus a tremor `tremorRate` times a second at
	-- `tremor` of the size. Aiming keeps `aim` of the gun's wander (the sights wander with it).
	viewmodel = { pitch = 2.5, yaw = 2.5, roll = 3 },
	camera = { pitch = 0.5, yaw = 0.5, roll = 0.6 },
	rate = 0.8,
	tremor = 0.3,
	tremorRate = 7,
	aim = 0.7,
})
