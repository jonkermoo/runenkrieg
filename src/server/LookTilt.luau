--!strict
-- Relays each soldier's look tilt (src/client/LookTilt) to the other players. The client's pitch is never trusted as
-- sent: Rules/LookTilt.sanitize drops anything that isn't a number and clamps and quantizes the rest. Only the latest
-- value per player is kept, and it goes out at most Config/Locomotion.LookTilt.Send.Rate times a second, so a client
-- sending faster gains nothing.
-- The head's turn (Net "HeadYaw", Config/Locomotion.LookTilt.Head) goes the same way, but only to soldiers within
-- Head.Send.Range of the turner (user 2026-10-20: only people nearby); a watcher who leaves the range gets 0 once.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Tilt = require(Shared.Config.Locomotion).LookTilt
local Send = Tilt.Send
local Head = Tilt.Head
local Rules = require(Shared.Rules.LookTilt)

local LookTilt = {}

type Entry = { pitch: number, follow: number, dirty: boolean, at: number }

function LookTilt.start()
	local remote = Net.event("LookPitch")
	local latest: { [Player]: Entry } = {}
	local headRemote = Net.event("HeadYaw")
	-- each turner's latest head turn, and what each watcher was last sent
	local heads: { [Player]: { yaw: number, at: number, sent: { [Player]: number } } } = {}

	headRemote.OnServerEvent:Connect(function(player, yaw)
		local y = Rules.sanitizeYaw(yaw, Head.Send.Step, Head.Max)
		if not y then
			return
		end
		local h = heads[player]
		if h then
			h.yaw = y
		else
			heads[player] = { yaw = y, at = 0, sent = {} }
		end
	end)

	remote.OnServerEvent:Connect(function(player, pitch, follow)
		local p, f = Rules.sanitize(pitch, follow, Send)
		if not p or not f then
			return
		end
		local e = latest[player]
		if not e then
			latest[player] = { pitch = p, follow = f, dirty = true, at = 0 }
		elseif e.pitch ~= p or e.follow ~= f then
			e.pitch, e.follow, e.dirty = p, f, true
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		latest[player] = nil
		heads[player] = nil
		for _, h in heads do
			h.sent[player] = nil
		end
	end)
	local function joined(player: Player)
		player.CharacterAdded:Connect(function()
			latest[player] = nil -- a new body starts upright
			heads[player] = nil
		end)
		-- a new player hears everyone's current tilt
		for _, e in latest do
			e.dirty = true
		end
	end
	Players.PlayerAdded:Connect(joined)
	for _, player in Players:GetPlayers() do
		joined(player)
	end

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for player, e in latest do
			local character = player.Character
			if e.dirty and character and now - e.at >= 1 / Send.Rate then
				e.dirty, e.at = false, now
				for _, other in Players:GetPlayers() do
					if other ~= player then
						remote:FireClient(other, character, e.pitch, e.follow)
					end
				end
			end
		end
		-- head turns: to every soldier in range whose last copy differs, 0 to one that left the range
		for player, h in heads do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root or now - h.at < 1 / Head.Send.Rate then
				continue
			end
			h.at = now
			for _, other in Players:GetPlayers() do
				local theirs = other.Character and other.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if other == player or not theirs then
					continue
				end
				local near = Rules.inRange((theirs.Position - root.Position).Magnitude, Head.Send.Range)
				local want = if near then h.yaw else (if h.sent[other] ~= nil then 0 else nil)
				if want ~= nil and h.sent[other] ~= want then
					h.sent[other] = want
					headRemote:FireClient(other, character, want)
				end
			end
		end
	end)
end

return LookTilt
