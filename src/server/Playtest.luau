--!strict
-- Two-player play tests on the playtest map (Config/Maps/Playtest; DEV place only, while Workspace has the attribute
-- set: workspace:SetAttribute("Playtest", true), and the map is built): each player who joins takes the side with fewer
-- players (West first), wears that side's uniform kit (the player's "Kit", src/server/Kits) and spawns, every life, on
-- that side's spawn (the dev teleport "Playtest<side>", src/server/DevTools). Until real teams (M13).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools)
local Map = require(Shared.Config.Maps.Playtest)
local DevTools = require(script.Parent.DevTools)

local Playtest = {}

local ATTRIBUTE = "Playtest"
local SIDE = "PlaytestSide" -- on the Player: the side it plays

local function sideFor(): string
	local count = { West = 0, East = 0 }
	for _, p in Players:GetPlayers() do
		local s = p:GetAttribute(SIDE)
		if s == "West" or s == "East" then
			count[s] += 1
		end
	end
	return if count.East < count.West then "East" else "West"
end

local function join(player: Player)
	local side = sideFor()
	player:SetAttribute(SIDE, side)
	if player:GetAttribute("Kit") == nil then
		player:SetAttribute("Kit", Map.sides[side].kit)
	end
	local function spawned(character: Model)
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait() -- after Roblox has stood it on its spawn
		DevTools.teleport(player, "Playtest" .. side)
	end
	player.CharacterAdded:Connect(spawned)
	if player.Character then
		task.spawn(spawned, player.Character)
	end
end

function Playtest.start()
	if game.PlaceId ~= Cfg.DevPlaceId or workspace:GetAttribute(ATTRIBUTE) ~= true then
		return
	end
	if not workspace:FindFirstChild(Map.name) then
		warn(`[Playtest] the attribute is set but the map isn't built: Greybox.build("{Map.name}")`)
		return
	end
	Players.PlayerAdded:Connect(join)
	for _, p in Players:GetPlayers() do
		join(p)
	end
end

return Playtest
