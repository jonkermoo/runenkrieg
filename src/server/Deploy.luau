--!strict
-- Spawning from the menus (user 2026-10-27): no character until the player deploys. A player who joins gets the title
-- screen, then the loadout menu (src/client/Menus); on every death the loadout menu opens again. The "Deploy" action
-- (Net "Loadout", src/server/Loadouts) spawns them once Config/Metrics.Combat.RespawnDelay has passed since their last
-- death (at once after the join). Each player's next life is settled ahead: the kit and looks are rolled at the join
-- and on each death (src/server/Kits, src/server/Bodies), and the menu shows that soldier in the picked class: a
-- dressed, anchored rig kept in the player's PlayerGui (only they get it) as "LoadoutPreview", rebuilt on every pick
-- and death, its primary in the hands (the client plays the hold).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Classes)
local Metrics = require(Shared.Config.Metrics)
local U = require(Shared.Config.Uniforms)
local Rules = require(Shared.Rules.Classes)
local Armory = require(script.Parent.Armory)
local Bodies = require(script.Parent.Bodies)
local Kits = require(script.Parent.Kits)
local Loadouts = require(script.Parent.Loadouts)

local Deploy = {}

local PREVIEW = "LoadoutPreview"

-- when each player last died (os.clock); none: never spawned or alive
local diedAt: { [Player]: number } = {}

local function alive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- Seconds until `player` may deploy (0: now).
function Deploy.wait(player: Player): number
	local at = diedAt[player]
	if not at then
		return 0
	end
	return math.max(Metrics.Combat.RespawnDelay - (os.clock() - at), 0)
end

-- The soldier `player` spawns as next, as class `key`: their next kit and looks, the class's helmet and primary.
local function preview(player: Player, key: string)
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return
	end
	local old = gui:FindFirstChild(PREVIEW)
	if old then
		old:Destroy()
	end
	local kit = Kits.next(player)
	local desc = Instance.new("HumanoidDescription")
	local rig = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
	rig.Name = PREVIEW
	for _, d in rig:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy()
		end
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local root = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	rig.PrimaryPart = root
	rig:SetAttribute("Kit", kit) -- (src/server/Kits)
	rig:SetAttribute("Class", key) -- (src/server/Loadouts: the class's helmet)
	rig:SetAttribute("Muted", true)
	rig:PivotTo(CFrame.new())
	rig.Parent = gui
	Bodies.apply(rig, player) -- in this player's next look
	local primary = Rules.gear(key, kit, C.Defs, U.Kits, C.Gear).Primary
	if primary then
		local tool = Armory.tool(primary, kit)
		local hold = tool:FindFirstChild("Hold", true) :: Motor6D
		hold.Part0 = rig:FindFirstChild("Torso") :: BasePart
		tool.Parent = rig
		rig:SetAttribute("Primary", primary) -- (src/client/Menus plays its ready hold)
	end
end

local function spawned(player: Player, character: Model)
	diedAt[player] = nil
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	humanoid.Died:Connect(function()
		diedAt[player] = os.clock()
	end)
end

function Deploy.start()
	Players.CharacterAutoLoads = false
	Loadouts.bind({
		changed = function(player: Player, why: string)
			if why == "Died" then
				diedAt[player] = os.clock()
				Kits.reroll(player)
				Bodies.reroll(player)
			end
			preview(player, Loadouts.picked(player))
		end,
		deploy = function(player: Player)
			if alive(player) or Deploy.wait(player) > 0 then
				return
			end
			diedAt[player] = nil
			player:LoadCharacter()
		end,
		fields = function(player: Player)
			if not player:FindFirstChildOfClass("PlayerGui") or not player.PlayerGui:FindFirstChild(PREVIEW) then
				preview(player, Loadouts.picked(player))
			end
			return { wait = Deploy.wait(player), alive = alive(player), kit = Kits.next(player) }
		end,
	})
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			spawned(player, character)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		diedAt[p] = nil
	end)
end

return Deploy
