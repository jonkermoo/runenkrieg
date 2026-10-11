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
	["walk and sprint step at a human pace"] = function()
		local walk, sprint = L.Animations.walk, L.Animations.sprint
		local walkSteps, sprintSteps = 2 / walk.cycle, 2 / sprint.cycle -- two steps per cycle
		assert(walkSteps >= 1.5 and walkSteps <= 2.5, `walk {walkSteps} steps/s`)
		assert(sprintSteps > walkSteps and sprintSteps <= 3.5, `sprint {sprintSteps} steps/s`)
	end,
	["speed thresholds split idle, walk and sprint"] = function()
		assert(L.IdleBelow > 0 and L.IdleBelow < M.Movement.AimWalkSpeed, "idle threshold must be under aim-walk")
		assert(L.SprintAbove > M.Movement.WalkSpeed, "a walk must never play the sprint cycle")
		assert(L.SprintAbove < M.Movement.SprintSpeed, "a sprint must play the sprint cycle")
		assert(L.PlaybackMin < 1 and L.PlaybackMax > 1, "playback clamp must include 1")
	end,
	["every movement animation has an asset id"] = function()
		for _, name in { "idle", "walk", "sprint", "climb", "toolnone" } do
			local a = L.Animations[name]
			assert(a and type(a.id) == "number" and a.id > 0, `missing animation {name}`)
		end
	end,
	["Roblox's footsteps are muted, its jump sound is kept"] = function()
		assert(L.SoundVolumes.Running == 0, "Roblox's footstep loop must be muted (Footsteps replaces it)")
		local jump = L.SoundVolumes.Jumping
		assert(jump == nil or jump > 0, "the default jump sound stays (user 2026-10-11)")
	end,
	["the jump has a cooldown"] = function()
		assert(M.Movement.JumpCooldown > 0 and M.Movement.JumpCooldown < 1, "jump cooldown should be short")
		assert(
			M.Movement.JumpApexGravityCut > 0 and M.Movement.JumpApexGravityCut < 1,
			"apex float cuts part of gravity"
		)
	end,
	["look tilt is a small share of the camera pitch"] = function()
		local t = L.LookTilt
		assert(t.Torso > 0 and t.Torso < 0.5, "the torso follows only part of the camera pitch")
		assert(t.TorsoMax <= 15, "the tilt cap keeps the soldier upright")
	end,
	["the default Animate script is replaced"] = function()
		local project = serde.decode("json", fs.readFile("default.project.json"))
		local scripts = project.tree.StarterPlayer.StarterCharacterScripts
		assert(scripts and scripts.Animate, "StarterCharacterScripts.Animate must override Roblox's default")
	end,
}
