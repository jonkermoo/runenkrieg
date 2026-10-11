--!strict
-- Footstep sounds (Config/Footsteps). Every character's walk / sprint tracks carry "Footstep" markers on the foot
-- plants; on each client, for every character (its own and other players'), a marker plays one short low step at
-- that character. Steps in the air (the cycles keep playing through a jump) are skipped. Nothing goes over the
-- network.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared").Config
local Cfg = require(Config.Footsteps)
local Loco = require(Config.Locomotion)

local Footsteps = {}

local WALK = "rbxassetid://" .. Loco.Animations.walk.id
local SPRINT = "rbxassetid://" .. Loco.Animations.sprint.id

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
		local ids = Cfg.Sounds
		local sound = Instance.new("Sound")
		sound.Name = "Footstep"
		sound.SoundId = "rbxassetid://" .. ids[rng:NextInteger(1, #ids)]
		sound.Volume = if track.Animation and track.Animation.AnimationId == SPRINT
			then Cfg.SprintVolume
			else Cfg.Volume
		sound.PlaybackSpeed = Cfg.Pitch + rng:NextNumber(-Cfg.PitchJitter, Cfg.PitchJitter)
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = Cfg.RollOffMin
		sound.RollOffMaxDistance = Cfg.RollOffMax
		sound.Parent = root
		sound.Ended:Once(function()
			sound:Destroy()
		end)
		sound:Play()
	end

	local hooked: { [AnimationTrack]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local function hook(track: AnimationTrack)
		local id = track.Animation and track.Animation.AnimationId
		if (id == WALK or id == SPRINT) and not hooked[track] then
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
