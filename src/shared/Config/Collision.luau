--!strict
-- Soldiers' collision groups (Rules/Collision; set by src/server/SoldierGroups). User 2026-11-04: "ai/players dont
-- collide with each other. this includes for camera (sometimes cameras gets stuck in a teammates head in third
-- person)", teammates only: a team's soldiers (players, bots and dev dummies) pass through each other and still bump
-- into the enemy's.
local Collision = {
	-- every soldier with no team, and everyone in a free-for-all match (Config/ZoneMatch.FreeForAllAttribute): they
	-- collide with each other. Other groups set against this one (debris, grenades, boundary walls, landing trees) are
	-- set alike against every team's group.
	Soldiers = "Characters",
	-- a team's soldiers: this .. its kit key (Config/Uniforms.Kits); they don't collide with each other
	TeamPrefix = "Characters_",
	-- the third-person camera's sweep (src/client/WeaponCamera): it hits what the Default group hits, except soldiers
	-- (anyone's) and the groups in `Through`, so a soldier between the camera and you never pulls it into their head
	Camera = "CameraSweep",
	Through = { "Debris", "Viewmodel" },
}

return table.freeze(Collision)
