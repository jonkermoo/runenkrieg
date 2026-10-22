--!strict
-- The blast flinch on the own soldier (Config/Flinch; src/server/Flinch decides who flinches and sends Net "Flinch"):
-- the soldier ducks a little and puts the right hand to the helmet. Played here, on the owner's client, so it
-- replicates to everyone. Checked again on arrival (nothing in the hands, not ragdolled, alive) and cut short when the
-- soldier is knocked down or draws something.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Flinch)
local Net = require(Shared.Net)

local Flinch = {}

function Flinch.start()
	local player = Players.LocalPlayer
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. Cfg.Animation.id
	task.spawn(function()
		ContentProvider:PreloadAsync({ anim }) -- (or the first flinch shows a frozen pose)
	end)

	local track: AnimationTrack? = nil
	local function stop()
		if track and track.IsPlaying then
			track:Stop(Cfg.Fade)
		end
	end

	local function onCharacter(character: Model)
		track = nil
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		local animator = humanoid:WaitForChild("Animator") :: Animator
		if player.Character ~= character then
			return
		end
		local t = animator:LoadAnimation(anim)
		t.Priority = Enum.AnimationPriority.Action2
		track = t
		character:GetAttributeChangedSignal("Ragdolled"):Connect(function()
			if character:GetAttribute("Ragdolled") == true then
				stop()
			end
		end)
		character:GetAttributeChangedSignal("Healing"):Connect(stop)
		character.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				stop()
			end
		end)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end

	Net.event("Flinch").OnClientEvent:Connect(function(weight: number)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if
			not track
			or not character
			or not humanoid
			or humanoid.Health <= 0
			or character:GetAttribute("Ragdolled") == true
			or character:FindFirstChildOfClass("Tool")
			or character:GetAttribute("Stowing") ~= nil
			or character:GetAttribute("Healing") ~= nil
		then
			return
		end
		local w = math.clamp(weight, 0, 1)
		if track.IsPlaying then
			track:AdjustWeight(math.max(track.WeightTarget, w), Cfg.Fade)
			return
		end
		track:Play(Cfg.Fade, w)
	end)
end

return Flinch
