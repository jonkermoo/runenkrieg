--!strict
-- The server's game mode (Config/Modes, Rules/Modes; user 2026-10-27: "we are also on conflicting maps, we will need an
-- admin panel for switching game modes"). Workspace's Mode attribute says which is live: "Admin" (Map 1, nothing
-- running: spawn on its test spawn), "FFA" (the zone-capture match on the playtest map, src/server/ZoneMatch) or
-- "Normal" (the frontline push on Map 1, src/server/Frontline). Only the live mode runs its spawns, match and zones.
-- The server starts in the place's saved mode (or FFA from the zone match's old Playtest switch); the admin panel
-- switches it (src/server/DevTools), and everyone alive respawns in the new one (the others are in the menus and
-- deploy into it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Modes)
local Rules = require(Shared.Rules.Modes)
local Frontline = require(script.Parent.Frontline)
local ZoneMatch = require(script.Parent.ZoneMatch)

local Modes = {}

local current = Cfg.Default

function Modes.current(): string
	return current
end

-- Runs `key` (stopping the live one); false (and the server stays as it is) if it can't start.
local function enter(key: string): boolean
	local was = current
	local matches: { [string]: any } = { FFA = ZoneMatch, Normal = Frontline }
	if matches[was] then
		matches[was].stop()
	end
	if matches[key] and not matches[key].start() then
		if matches[was] then
			matches[was].start()
		end
		return false
	end
	current = key
	workspace:SetAttribute(Cfg.Attribute, key)
	return true
end

-- Switches the server to `key` and respawns everyone alive in it; false if it isn't a mode it can switch to.
function Modes.switch(key: string): boolean
	if not Rules.switchable(Cfg, key, current) or not enter(key) then
		return false
	end
	for _, p in Players:GetPlayers() do
		local humanoid = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			task.spawn(function()
				p:LoadCharacter()
			end)
		end
	end
	return true
end

function Modes.start()
	local key = Rules.initial(Cfg, workspace:GetAttribute(Cfg.Attribute), workspace:GetAttribute(Cfg.Legacy.attribute))
	if not enter(key) then
		enter(Cfg.Default)
	end
end

return Modes
