--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local L = require("../src/shared/Config/Locomotion")
local M = require("../src/shared/Config/Metrics")

return {
	["walk and sprint cycles are keyed at the Metrics speeds"] = function()
		assert(L.Animations.walk.speed == M.Movement.WalkSpeed, "walk cycle speed drifted from Metrics")
		assert(L.Animations.sprint.speed == M.Movement.SprintSpeed, "sprint cycle speed drifted from Metrics")
	end,
	["speed thresholds split idle, walk and sprint"] = function()
		assert(L.IdleBelow > 0 and L.IdleBelow < M.Movement.AimWalkSpeed, "idle threshold must be under aim-walk")
		assert(L.SprintAbove > M.Movement.WalkSpeed, "a walk must never play the sprint cycle")
		assert(L.SprintAbove < M.Movement.SprintSpeed, "a sprint must play the sprint cycle")
		assert(L.PlaybackMin < 1 and L.PlaybackMax > 1, "playback clamp must include 1")
	end,
	["every movement animation has an asset id"] = function()
		for _, name in { "idle", "walk", "sprint", "jump", "fall", "land", "climb", "toolnone" } do
			local a = L.Animations[name]
			assert(a and type(a.id) == "number" and a.id > 0, `missing animation {name}`)
		end
	end,
	["the default Animate script is replaced"] = function()
		local project = serde.decode("json", fs.readFile("default.project.json"))
		local scripts = project.tree.StarterPlayer.StarterCharacterScripts
		assert(scripts and scripts.Animate, "StarterCharacterScripts.Animate must override Roblox's default")
	end,
}
