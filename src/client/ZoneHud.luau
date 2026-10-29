--!strict
-- The zone match's clock and point leader (user 2026-10-29: "there will just be a basic timer and it will state who the
-- current point leader is"; layout src/shared/ui/CombatHud.json "Match"), top centre while the server's mode is FFA:
-- the match's time left and its leader (the winner, and the time to the next match, during the results). Read from
-- the marker's attributes (src/server/ZoneMatch; Config/ZoneMatch). The leader's glow is everyone else's to see: on
-- the leader's own screen it's off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.ZoneMatch)
local ModesCfg = require(Shared.Config.Modes)
local Map = require(Shared.Config.Maps.Playtest)
local Rules = require(Shared.Rules.ZoneMatch)
local HudKit = require(script.Parent.HudKit)

local ZoneHud = {}

local function named(id: unknown, me: Player): string?
	if type(id) ~= "number" then
		return nil
	end
	if id == me.UserId then
		return "You"
	end
	local p = Players:GetPlayerByUserId(id)
	return if p then p.DisplayName else nil
end

local function score(id: number): number
	local p = Players:GetPlayerByUserId(id)
	return math.floor(((p and p:GetAttribute(Cfg.ScoreAttribute) :: number?) or 0) + 1e-6)
end

function ZoneHud.start()
	local me = Players.LocalPlayer
	local panel = HudKit.panel("Match", "ZoneHud")
	RunService.Heartbeat:Connect(function()
		local root = workspace:FindFirstChild(Map.name)
		local zone = root and root:FindFirstChild(Cfg.MarkerName)
		local on = zone ~= nil and workspace:GetAttribute(ModesCfg.Attribute) == "FFA"
		panel.gui.Enabled = on
		if not zone or not on then
			return
		end
		local endsAt = (zone:GetAttribute("EndsAt") :: number?) or 0
		panel.set("clock", Rules.clock(endsAt - workspace:GetServerTimeNow()))
		local leader = zone:GetAttribute(Cfg.LeaderAttribute)
		local name = named(leader, me)
		if zone:GetAttribute("Phase") == "Results" then
			local winner = named(zone:GetAttribute("Winner"), me)
			panel.set("leader", if winner == "You" then "You win!" elseif winner then `{winner} wins` else "No winner")
		elseif name then
			panel.set("leader", `Leader: {name} ({score(leader :: number)})`)
		else
			panel.set("leader", "No leader yet")
		end
		-- (my own glow: off on my screen)
		local glow = me.Character and me.Character:FindFirstChild(Cfg.Leader.name)
		if glow and glow:IsA("Highlight") and glow.Enabled then
			glow.Enabled = false
		end
	end)
end

return ZoneHud
