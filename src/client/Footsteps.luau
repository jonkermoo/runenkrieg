--!strict
-- Footstep sounds (Config/Footsteps, Rules/Footsteps). Every soldier's walk / sprint / crouch tracks carry "Footstep"
-- markers on the foot plants; on each client, for every character (its own, other players', and bots, whose tracks
-- the server plays and replicates), a marker plays one step at that character: the recording for the ground under it
-- (terrain by material, a part by its building section's class or its name), as loud as its gait. Steps in the air
-- (the cycles keep playing through a jump) and steps too far from the camera are skipped. Nothing goes over the
-- network. Every step comes out of one sheet sound (a region per recording); each character keeps two loaded copies
-- and alternates them, so one step still ringing isn't cut off: a Sound made at the moment of the step starts ~0.33 s
-- late (it loads first), a ready one in ~0.03 s.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Footsteps)
local Loco = require(Shared.Config.Locomotion)
local BotCfg = require(Shared.Config.Bots)
local Rules = require(Shared.Rules.Footsteps)
local Audio = require(script.Parent.Audio)

local Footsteps = {}

local Anims = require(Shared.Rules.MovementSet).animations(Loco) -- the set in play
local GAIT = {
	["rbxassetid://" .. Anims.walk.id] = "walk",
	["rbxassetid://" .. Anims.sprint.id] = "sprint",
	["rbxassetid://" .. Anims.crouchWalk.id] = "crouch",
}

local rng = Random.new()
local attached: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- what the ray landed on, as Rules/Footsteps.surface takes it
local function surfaceOf(hit: RaycastResult): string
	local part = hit.Instance
	if part == workspace.Terrain then
		return Rules.surface(Cfg, hit.Material.Name, nil, nil)
	end
	local class = part:GetAttribute("Class")
	if class == nil and part.Parent then
		class = part.Parent:GetAttribute("Class")
	end
	return Rules.surface(Cfg, nil, if type(class) == "string" then class else nil, part.Name)
end

local function attach(character: Model)
	if attached[character] then
		return
	end
	attached[character] = true
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

	-- two copies of the sheet, made once and kept loaded
	local pool: { Sound } = {}
	for i = 1, 2 do
		local sound = Instance.new("Sound")
		sound.Name = "Footstep" .. i
		sound.SoundId = "rbxassetid://" .. Cfg.Sheet
		sound.PlaybackRegionsEnabled = true
		Audio.spatial(sound, "Footstep") -- realistic falloff (Config/Audio)
		sound.Parent = root
		pool[i] = sound
	end
	local turn = 1
	local lastPick: { [string]: number } = {}

	local function step(track: AnimationTrack, gait: string)
		if track.WeightCurrent < 0.5 or humanoid.Health <= 0 then
			return
		end
		local now = os.clock()
		if now - last < Cfg.MinInterval then
			return
		end
		local camera = workspace.CurrentCamera
		if camera and not Rules.heard(Cfg, gait, (camera.CFrame.Position - root.Position).Magnitude) then
			return
		end
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -Cfg.GroundProbe, 0), params)
		if not hit then
			return -- airborne
		end
		last = now
		local surface = surfaceOf(hit)
		-- a different recording from this surface's last one
		local count = Cfg.Count[surface]
		local k = rng:NextInteger(1, count)
		if k == lastPick[surface] and count > 1 then
			k = k % count + 1
		end
		lastPick[surface] = k
		local start, length = Rules.slot(Cfg, surface, k)
		local sound = pool[turn]
		turn = turn % #pool + 1
		local own = character == Players.LocalPlayer.Character
		sound.Volume = Rules.volume(Cfg, gait, surface, own)
		sound.PlaybackSpeed = Cfg.Pitch + rng:NextNumber(-Cfg.PitchJitter, Cfg.PitchJitter)
		sound.PlaybackRegion = NumberRange.new(start, start + length)
		sound.TimePosition = start
		sound:Play()
	end

	local hooked: { [AnimationTrack]: boolean } = setmetatable({}, { __mode = "k" }) :: any
	local function hook(track: AnimationTrack)
		local gait = track.Animation and GAIT[track.Animation.AnimationId]
		if gait and not hooked[track] then
			hooked[track] = true -- a track fires AnimationPlayed on every Play
			track:GetMarkerReachedSignal("Footstep"):Connect(function()
				step(track, gait)
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
	-- bots: server-owned soldiers, their tracks replicated (src/server/Bots/Animate)
	local function bot(m: Instance)
		if m:IsA("Model") then
			task.spawn(attach, m)
		end
	end
	CollectionService:GetInstanceAddedSignal(BotCfg.Tag):Connect(bot)
	for _, m in CollectionService:GetTagged(BotCfg.Tag) do
		bot(m)
	end
end

return Footsteps
