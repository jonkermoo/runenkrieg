--!strict
-- Relays each soldier's look tilt (src/client/LookTilt) to the other players. The client's pitch is never trusted as
-- sent: Rules/LookTilt.sanitize drops anything that isn't a number and clamps and quantizes the rest. Only the latest
-- value per player is kept, and it goes out at most Config/Locomotion.LookTilt.Send.Rate times a second, so a client
-- sending faster gains nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Send = require(Shared.Config.Locomotion).LookTilt.Send
local Rules = require(Shared.Rules.LookTilt)

local LookTilt = {}

type Entry = { pitch: number, follow: number, dirty: boolean, at: number }

function LookTilt.start()
	local remote = Net.event("LookPitch")
	local latest: { [Player]: Entry } = {}

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
	end)
	local function joined(player: Player)
		player.CharacterAdded:Connect(function()
			latest[player] = nil -- a new body starts upright
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
	end)
end

return LookTilt
