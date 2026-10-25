--!strict
-- The blast flinch on the server (Config/Flinch, Rules/Flinch; user 2026-10-22): after src/server/Damage.blast has hurt
-- and flung whom it reaches, every soldier it didn't knock, within the flinch band, with nothing in the hands and not
-- down ducks a little and puts a hand to the helmet. A player's soldier is told through Net "Flinch" (its own client
-- plays it, so it replicates to everyone: src/client/Flinch); a DEV dummy plays it here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Flinch)
local B = require(Shared.Config.Damage).Blast
local Blast = require(Shared.Rules.Blast)
local Rules = require(Shared.Rules.Flinch)
local Net = require(Shared.Net)

local Flinch = {}

-- something in the hands: a weapon, one being put away (src/server/Armory keeps a copy), or healing someone
function Flinch.busy(character: Model): boolean
	return character:FindFirstChildOfClass("Tool") ~= nil
		or character:FindFirstChild("Stowing") ~= nil
		or character:GetAttribute("Healing") ~= nil
end

-- a dummy's flinch tracks, the hand and the dip (plain table, dropped with its animator: docs/KNOWN_TRAPS.md, the
-- 64-track limit). DEV dummies stand still, so they dip too.
local tracks: { [Animator]: { AnimationTrack } } = {}
local function dummyTracks(humanoid: Humanoid): { AnimationTrack }?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return nil
	end
	if not tracks[animator] then
		local set = {}
		for _, id in { Cfg.Animation.id, Cfg.Dip.id } do
			local a = Instance.new("Animation")
			a.AnimationId = "rbxassetid://" .. id
			local t = animator:LoadAnimation(a)
			t.Priority = Enum.AnimationPriority.Action2
			table.insert(set, t)
		end
		tracks[animator] = set
		animator.Destroying:Once(function()
			tracks[animator] = nil
		end)
	end
	return tracks[animator]
end

-- A `kg` blast at `position` (its splinters wounding to `wound`, nil: none) has gone off; `knocked`: the soldiers it
-- hurt and flung, `soldiers`: everyone it could reach (src/server/Damage).
function Flinch.blast(position: Vector3, kg: number, wound: number?, knocked: { [Model]: boolean }, soldiers: { Model })
	local knock, outer = Rules.band(Blast.reachOf(B.Soldier.from, kg, B), wound, Blast.reachOf(Cfg.kpa, kg, B), Cfg)
	local now = os.clock()
	for _, character in soldiers do
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local torso = character:FindFirstChild("Torso") :: BasePart?
		if not humanoid or not torso then
			continue
		end
		local down = humanoid.Health <= 0 or character:GetAttribute("Ragdolled") == true
		local d = (torso.Position - position).Magnitude
		local weight = Rules.weight(d, knock, outer, knocked[character] == true, Flinch.busy(character), down, Cfg)
		local last = character:GetAttribute("FlinchAt") :: number?
		if not weight or (last and now - last < Cfg.Again) then
			continue
		end
		character:SetAttribute("FlinchAt", now)
		local player = Players:GetPlayerFromCharacter(character)
		if player then
			Net.event("Flinch"):FireClient(player, weight)
		else
			for _, t in dummyTracks(humanoid) or {} do
				t:Play(Cfg.Fade, weight)
			end
		end
	end
end

return Flinch
