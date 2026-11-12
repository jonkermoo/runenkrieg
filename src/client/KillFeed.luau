--!strict
-- The in-match essentials the review asked for (review 2026-11-12), each a panel of src/shared/ui/CombatHud.json built
-- by HudKit, in the combat HUD's look:
-- - Vitals: the soldier's health, a thin bar over the kit list with the number, red once low (Config/Hud.Vitals).
-- - Feed: the last few deaths top right ("Killer  weapon  Victim", the names in their side's colour; Net "Kill" from
--   src/server/Loadouts), each for Config/Hud.Feed.seconds.
-- - Death: your own death in a line in the middle, "Killed by X (weapon)", until the loadout screen comes back.
-- All off on the title and loadout screens and in the match's cutscenes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HudCfg = require(Shared.Config.Hud)
local Palette = require(Shared.Config.Palette)
local Net = require(Shared.Net)
local HudKit = require(script.Parent.HudKit)

local KillFeed = {}

local NAMES = ((Palette.UI :: any).Grimoire.Name or {}) :: { [string]: { number } }

-- `name` in its side's colour (rich text), plain when the side is unknown
local function tinted(name: string, kit: any): string
	local c = type(kit) == "string" and NAMES[kit]
	local safe = name:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
	if not c then
		return safe
	end
	return `<font color="#{Color3.fromRGB(c[1], c[2], c[3]):ToHex()}">{safe}</font>`
end

function KillFeed.start()
	local player = Players.LocalPlayer
	local V, F = HudCfg.Vitals, HudCfg.Feed
	local vitals = HudKit.panel("Vitals", "Vitals", true)
	local feed = HudKit.panel("Feed", "KillFeed")
	local death = HudKit.panel("Death", "DeathLine")
	local lines = { feed.node.Feed1 :: TextLabel, feed.node.Feed2 :: TextLabel, feed.node.Feed3 :: TextLabel }
	for _, l in lines do
		l.RichText = true
	end
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local function screenOn(name: string): boolean
		local g = playerGui:FindFirstChild(name)
		return g ~= nil and g:IsA("ScreenGui") and g.Enabled
	end

	local entries: { { text: string, at: number } } = {}
	local deathUntil = 0
	Net.event("Kill").OnClientEvent:Connect(
		function(killer: any, killerKit: any, victim: any, victimKit: any, weapon: any, head: any, victimPlayer: any)
			if type(victim) ~= "string" then
				return
			end
			local how = if type(weapon) == "string"
				then `  {weapon}{if head == true then " (head)" else ""}  `
				else "  ✕  "
			local text = if type(killer) == "string"
				then `{tinted(killer, killerKit)}{how}{tinted(victim, victimKit)}`
				else `{tinted(victim, victimKit)} died`
			table.insert(entries, 1, { text = text, at = os.clock() })
			while #entries > #lines do
				table.remove(entries)
			end
			if victimPlayer == player then
				death.set(
					"death",
					if type(killer) == "string"
						then `Killed by {killer}{if type(weapon) == "string" then ` ({weapon})` else ""}`
						else "You died"
				)
				deathUntil = os.clock() + F.deathSeconds
			end
		end
	)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local menus = screenOn("TitleScreen")
			or screenOn("LoadoutMenu")
			or screenOn("MatchCutscene")
			or screenOn("EndScenes")
		-- the health bar
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local alive = humanoid ~= nil and humanoid.Health > 0 and humanoid.MaxHealth > 0
		vitals.gui.Enabled = alive and not menus
		if alive then
			local h = humanoid :: Humanoid
			local share = h.Health / h.MaxHealth
			vitals.fill("HealthBar", share, HudKit.rgb(if share <= V.low then "countLow" else "readout"))
			vitals.set("health", `Health {math.ceil(h.Health)}`)
		end
		-- the feed (newest at the top, each gone after its time)
		for i = #entries, 1, -1 do
			if now - entries[i].at > F.seconds then
				table.remove(entries, i)
			end
		end
		for i, l in lines do
			local e = entries[i]
			l.Text = if e then e.text else ""
		end
		feed.gui.Enabled = #entries > 0 and not screenOn("TitleScreen") and not screenOn("MatchCutscene")
		-- your death's line, until the loadout screen is back (or its time is up)
		death.gui.Enabled = now < deathUntil and not menus
	end)
end

return KillFeed
