--!strict
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local L = require("../src/shared/Config/Locomotion")
local MovementSet = require("../src/shared/Rules/MovementSet")
local W = require("../src/shared/Config/Weapons")
local A = MovementSet.animations(L) -- the movement set in play
local M = require("../src/shared/Config/Metrics")

return {
	["walk and sprint cycles are keyed at the Metrics speeds"] = function()
		assert(A.walk.speed == M.Movement.WalkSpeed, "walk cycle speed drifted from Metrics")
		assert(A.sprint.speed == M.Movement.SprintSpeed, "sprint cycle speed drifted from Metrics")
	end,
	["walk and sprint step at a human pace"] = function()
		local walk, sprint = A.walk, A.sprint
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
			local a = A[name]
			assert(a and type(a.id) == "number" and a.id > 0, `missing animation {name}`)
		end
	end,
	["both movement sets have every animation, keyed at the Metrics speeds and in step with the holds"] = function()
		assert(L.Sets[L.Set], `unknown movement set {L.Set}`)
		for set, def in L.Sets do
			local a = MovementSet.animations({ Animations = L.Animations, Sets = L.Sets, Set = set })
			for _, name in { "idle", "walk", "sprint", "crouchIdle", "crouchWalk", "jump", "fall", "land", "climb" } do
				assert(a[name] and a[name].id > 0, `{set}: missing {name}`)
			end
			assert(a.walk.speed == M.Movement.WalkSpeed and a.sprint.speed == M.Movement.SprintSpeed, `{set}: speeds`)
			-- the moving holds keep step with these keyed lengths (rifle.luau)
			assert(
				a.walk.keyed == 0.76 and a.sprint.keyed == 0.56 and a.crouchWalk.keyed == 1.0,
				`{set}: keyed lengths`
			)
			for weapon, holds in def.Holds or {} do
				assert(W[weapon], `{set}: holds for unknown weapon {weapon}`)
				for hold, id in holds do
					assert(W[weapon].holds[hold], `{set}: {weapon} has no {hold} hold to replace`)
					assert(type(id) == "number" and id > 0, `{set}: {weapon}.{hold} needs an id`)
				end
			end
		end
	end,
	["transitions blend smoothly, never snap"] = function()
		-- user 2026-10-20: "make movement always smooth and never snappy"
		assert(L.Fade >= 0.25 and L.Fade <= 0.5, `ground cycle fade {L.Fade}`)
		assert(L.HoldFade >= 0.2 and L.HoldFade <= 0.4, `hold fade {L.HoldFade}`)
		for _, k in { "JumpFade", "FallFade", "LandFade" } do
			assert(L.Air[k] >= 0.08 and L.Air[k] <= 0.3, `{k} {L.Air[k]}`)
		end
	end,
	["air: take-off, tuck and landing have ids; the landing is lighter on the move"] = function()
		for _, name in { "jump", "fall", "land" } do
			local a = A[name]
			assert(a and type(a.id) == "number" and a.id > 0, `missing animation {name}`)
		end
		local air = L.Air
		assert(air.LandWeightMoving > 0 and air.LandWeightMoving < air.LandWeight, "a moving landing blends lighter")
		assert(air.FallDelay > 0 and air.FallDelay < air.LandMinAir, "a step down shows neither the tuck nor a landing")
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
	["sprint only forward: the cone excludes pure strafing and backing up"] = function()
		assert(L.SprintCone >= 20 and L.SprintCone < 90, `SprintCone {L.SprintCone} must be under 90 degrees`)
	end,
	["crouch: its walk is keyed at the crouch speed, slower than walking"] = function()
		local c = A.crouchWalk
		assert(c.speed == M.Movement.CrouchSpeed, "crouch walk speed drifted from Metrics")
		assert(M.Movement.CrouchSpeed < M.Movement.AimWalkSpeed, "crouching is slower than aim-walking")
		assert(A.crouchIdle.id > 0 and c.id > 0, "crouch animations need ids")
	end,
}
