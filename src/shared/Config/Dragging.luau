--!strict
-- Dragging a downed teammate (user 2026-10-22: "add dragging ragdolled teammates"; design approved the same day).
-- Rules/Dragging decides, src/server/Dragging applies (the body's physics: the server's), src/client/Dragging picks the
-- body, shows the prompt and plays the pull. Data only.
-- Look at a knocked-down (ragdolled), living teammate in reach and press the Drag key (Config/Settings Key_Drag, G);
-- again to let go. Teammates only (Rules/Teams). While dragging: walking slowly, no sprint, jump or aim, nothing in the
-- hands, crouched (bent over the body), facing the one dragged. The dragged soldier never gets up mid-drag: once let go, the usual settle and
-- get-up wait starts over (src/server/Ragdoll). It ends on the Drag key, the dragger knocked down, hit or dead, the
-- dragged soldier dead, a weapon drawn, a heal started, or the body caught Break studs behind. Once it ends, the
-- dragger takes out again whatever they held before the drag (user 2026-10-26), if their hands are still free.

local Dragging = {
	Range = 6, -- studs between the two soldiers' roots to start a drag (and the prompt shows)
	Break = 8, -- studs apart (roots) at which the drag lets go: the body caught on something
	PickCone = 25, -- the client's pick: the downed teammate in Range nearest the look, within this many degrees of it
	StartSlack = 1.5, -- studs the server allows past Range when a start arrives (lag)
	AskGap = 0.25, -- seconds between a player's drag requests the server takes (rate limit)
	Speed = 5, -- the dragger's (crouched) walk speed (studs/s; crouch-walk is 6, walk 10)

	-- The pull: an AlignPosition from each of the dragged body's `Legs` at its ankle (`Ankle`, in the leg's axes: its
	-- bottom) to a point by the dragger's hands (`Grip`, in the HumanoidRootPart's axes: low, in front). By the legs
	-- (user 2026-10-26: by the collar the dragger stood on the body and floated), so the body trails away from the
	-- dragger head last. It pulls the body only (the dragger isn't yanked back), at most `MaxForce` in all (shared by
	-- the legs), so the body slides and still catches on walls.
	Legs = { "Left Leg", "Right Leg" },
	Ankle = { 0, -0.9, 0 },
	Grip = { 0, -1.85, -1.4 }, -- (where the DragPull hands hold)
	MaxForce = 6000,
	MaxVelocity = 12, -- studs/s the collar may chase the grip at
	Responsiveness = 25,

	-- The dragger's pull (tools/animation/dragging.luau): both hands low on the collar, a slow tug, looping over the
	-- crouch walk (the dragger crouches while dragging: src/client/Stance).
	Animation = { id = 90887292928815 }, -- DragPull
	Fade = 0.2,

	-- The prompt over the body (src/client/Dragging), drawn like the heal prompt.
	Prompt = { Text = "Drag", Size = { 120, 30 }, Above = 1.5, TextSize = 16, Transparency = 0.15 },
}

return table.freeze(Dragging)
