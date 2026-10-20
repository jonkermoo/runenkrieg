--!strict
-- Footstep sounds (Config/Footsteps). Every character's walk / sprint tracks carry "Footstep" markers on the foot
-- plants; on each client, for every character (its own and other players'), a marker plays one short low step at
-- that character. Steps in the air (the cycles keep playing through a jump) are skipped. Nothing goes over the
-- network. Each character keeps one ready Sound per step sound and reuses them: a Sound made at the moment of the
-- step starts ~0.33 s late (it loads first), a ready one in ~0.03 s.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared").Config
local Cfg = require(Config.Footsteps)
local Loco = require(Config.Locomotion)
local Audio = require(script.Parent.Audio)

local Footsteps = {}

local Anims = require(ReplicatedStorage.Shared.Rules.MovementSet).animations(Loco) -- the set in play
local WALK = "rbxassetid://" .. Anims.walk.id
local SPRINT = "rbxassetid://" .. Anims.sprint.id
local CROUCH = "rbxassetid://" .. Anims.crouchWalk.id

local rng = Random.new()

local function attach(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end
	local animator = humanoid:WaitForChild("Animator", 10) :: Animator?
	if not animator then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.RespectCanCollide = true
	params.IgnoreWater = false
	local last = 0

	-- the step sounds, made once and kept loaded
	local pool: { Sound } = {}
	for i, id in Cfg.Sounds do
		local sound = Instance.new("Sound")
		sound.Name = "Footstep" .. i
		sound.SoundId = "rbxassetid://" .. id
		Audio.spatial(sound, "Footstep") -- realistic falloff (Config/Audio)
		sound.Parent = root
		pool[i] = sound
	end
	local lastSound = 0

	local function step(track: AnimationTrack)
		if track.WeightCurrent < 0.5 or humanoid.Health <= 0 then
			return
		end
		local now = os.clock()
		if now - last < Cfg.MinInterval then
			return
		end
		if not workspace:Raycast(root.Position, Vector3.new(0, -Cfg.GroundProbe, 0), params) then
			return -- airborne
		end
		last = now
		-- a different sound from the last step, so one still ringing isn't cut off
		local i = rng:NextInteger(1, #pool)
		if i == lastSound and #pool > 1 then
			i = i % #pool + 1
		end
		lastSound = i
		local sound = pool[i]
		sound.Volume = if track.Animation and track.Animation.AnimationId == SPRINT
			then Cfg.SprintVolume
			else Cfg.Volume
		sound.PlaybackSpeed = Cfg.Pitch + rng:NextNumber(-Cfg.PitchJitter, Cfg.PitchJitter)
		sound.TimePosition = 0
		sound:Play()
	end

	local hooked: { [AnimationTrack]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local function hook(track: AnimationTrack)
		local id = track.Animation and track.Animation.AnimationId
		if (id == WALK or id == SPRINT or id == CROUCH) and not hooked[track] then
			hooked[track] = true -- a track fires AnimationPlayed on every Play
			track:GetMarkerReachedSignal("Footstep"):Connect(function()
				step(track)
			end)
		end
	end
	animator.AnimationPlayed:Connect(hook)
	for _, t in animator:GetPlayingAnimationTracks() do
		hook(t)
	end
end

function Footsteps.start()
	local function watch(player: Player)
		player.CharacterAdded:Connect(attach)
		if player.Character then
			task.spawn(attach, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
end

return Footsteps
