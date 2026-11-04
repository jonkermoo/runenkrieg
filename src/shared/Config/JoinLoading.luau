--!strict
-- The loading screen on joining a server (user 2026-11-04: "the main menu should not even be visible until the
-- current map is done loading"; not between matches): src/client/Menus holds it until the match's map is streamed in
-- and its meshes, textures and decals preloaded (Rules/JoinLoading), then shows the title screen.
return table.freeze({
	Max = 45, -- seconds at the most before the title screen shows anyway (a slow connection never stuck here)
	Spacing = 400, -- studs at the most between the spots streamed in across the map's bounds
	Batch = 40, -- assets preloaded at a time
	Hold = 0.4, -- seconds the full bar stays before the title screen
	BuiltWait = 15, -- seconds at the most waiting for the map's model to stand in Workspace
})
