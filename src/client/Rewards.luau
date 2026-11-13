--!strict
-- The rewards popup (user 2026-11-12: "show the Marks you earned and who you killed in a short popup"): right of the
-- crosshair (src/shared/ui/Scoreboard.json Rewards, Config/Hud.Rewards), each Marks award the server pays you (Net
-- "Reward" from src/server/Loadouts.award). The newest on two lines, "+10 Marks" over "Killed [BOT] Hans Weber
-- (head)", older ones one line each under it, each fading after its time. A headshot's bonus joins its kill's line;
-- building and healing gather into one running line while they keep paying. Off on the title and loadout screens and
-- in the match's cutscenes.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HudCfg = require(Shared.Config.Hud) :: any
local Palette = require(Shared.Config.Palette)
local Net = require(Shared.Net)
local Spec = require(Shared.ui.Scoreboard) :: any
local HudKit = require(script.Parent.HudKit)

local Rewards = {}

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

-- Marks as shown: whole, or to a tenth under 10 (a few swings of building pay fractions)
local function marks(n: number): string
	if n >= 10 or math.abs(n - math.floor(n + 0.5)) < 0.05 then
		return tostring(math.floor(n + 0.5))
	end
	return string.format("%.1f", n)
end

type Entry = { reason: string, marks: number, who: string?, kit: string?, head: boolean, at: number }

-- what the entry was for: "Killed [BOT] Hans Weber (head)", "Building"
local function what(e: Entry): string
	local R = HudCfg.Rewards
	local words = R.words[e.reason] or e.reason
	local who = if e.who then ` {tinted(e.who, e.kit)}` else ""
	return `{words}{who}{if e.head then " (head)" else ""}`
end

function Rewards.start()
	local R = HudCfg.Rewards
	local player = Players.LocalPlayer
	local popup = HudKit.panel("Rewards", "Rewards", false, Spec)
	local n = popup.node
	local top, sub = n.RewardMarks :: TextLabel, n.RewardWhat :: TextLabel
	local older = { n.Reward2 :: TextLabel, n.Reward3 :: TextLabel, n.Reward4 :: TextLabel }
	local all = { top, sub, older[1], older[2], older[3] }
	for _, l in all do
		l.RichText = true
	end
	local countHex = HudKit.rgb("count"):ToHex()
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local function screenOn(name: string): boolean
		local g = playerGui:FindFirstChild(name)
		return g ~= nil and g:IsA("ScreenGui") and g.Enabled
	end

	local entries: { Entry } = {}
	local function push(e: Entry)
		table.insert(entries, 1, e)
		while #entries > 1 + #older do
			table.remove(entries)
		end
	end
	Net.event("Reward").OnClientEvent:Connect(function(reason: any, paid: any, who: any, whoKit: any)
		if type(reason) ~= "string" or type(paid) ~= "number" or paid <= 0 then
			return
		end
		local now = os.clock()
		local name = if type(who) == "string" then who else nil
		local kit = if type(whoKit) == "string" then whoKit else nil
		-- a headshot's bonus joins its kill (paid just after it)
		if reason == "Headshot" then
			local last = entries[1]
			if last and last.reason == "Kill" and last.who == name then
				last.marks += paid
				last.head = true
				last.at = now
				return
			end
		end
		-- building and healing run on in one line
		local key = R.gathered[reason]
		if key then
			for i, e in entries do
				if e.reason == key and now - e.at <= R.gather then
					e.marks += paid
					e.at = now
					table.remove(entries, i)
					table.insert(entries, 1, e)
					return
				end
			end
			reason = key
		end
		push({ reason = reason, marks = paid, who = name, kit = kit, head = false, at = now })
	end)

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for i = #entries, 1, -1 do
			if now - entries[i].at > R.seconds then
				table.remove(entries, i)
			end
		end
		local menus = screenOn("TitleScreen")
			or screenOn("LoadoutMenu")
			or screenOn("MatchCutscene")
			or screenOn("EndScenes")
		popup.gui.Enabled = #entries > 0 and not menus
		if not popup.gui.Enabled then
			return
		end
		local function fade(l: TextLabel, e: Entry?, dim: number)
			if not e then
				l.Text = ""
				return
			end
			local left = R.seconds - (now - e.at)
			local t = 1 - math.clamp(left / R.fade, 0, 1)
			l.TextTransparency = math.max(t, dim)
			l.TextStrokeTransparency = math.max(t, dim)
		end
		local first = entries[1]
		top.Text = `+{marks(first.marks)} Marks`
		sub.Text = what(first)
		fade(top, first, 0)
		fade(sub, first, 0)
		for i, l in older do
			local e = entries[i + 1]
			l.Text = if e then `<font color="#{countHex}">+{marks(e.marks)}</font>  {what(e)}` else ""
			fade(l, e, 0.15 * i)
		end
	end)
end

return Rewards
