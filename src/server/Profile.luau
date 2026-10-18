--!strict
-- The player profile (DataStore Config/Settings.Store, one entry per user id). For now it holds the settings
-- (Config/Settings.Field): loaded on join into the Player's "Setting_<Key>" attributes, which replicate to the client
-- (src/client/Settings), and saved from the client's Net "SaveSettings" (only valid entries, Rules/Settings.clean).
-- Written when changed every AutosaveEvery seconds, on leaving and on shutdown. Without DataStore access (Studio
-- without API access, an outage) settings last the session only.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Settings)
local Net = require(Shared.Net)
local R = require(Shared.Rules.Settings)

local Profile = {}

type Session = { settings: { [string]: any }, loaded: boolean, dirty: boolean, lastSave: number }

local sessions: { [Player]: Session } = {}
local store: DataStore? = nil

local function key(player: Player): string
	return tostring(player.UserId)
end

local function load(player: Player)
	local s: Session = { settings = {}, loaded = false, dirty = false, lastSave = 0 }
	sessions[player] = s
	if store then
		local ok, data = pcall(function()
			return (store :: DataStore):GetAsync(key(player))
		end)
		if not ok then
			warn(`[Profile] load failed for {player.UserId}: {data}`)
		elseif type(data) == "table" then
			s.settings = R.clean(Cfg.Options :: any, data[Cfg.Field], Cfg.MaxKeyName)
		end
	end
	if sessions[player] ~= s then
		return -- left while loading
	end
	for k, v in s.settings do
		player:SetAttribute("Setting_" .. k, v)
	end
	s.loaded = true
end

local function save(player: Player)
	local s = sessions[player]
	if not store or not s or not s.loaded or not s.dirty then
		return
	end
	s.dirty = false
	local settings = table.clone(s.settings)
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(player), function(old: any)
			local data = if type(old) == "table" then old else {}
			data[Cfg.Field] = settings -- (other profile fields kept)
			return data
		end)
	end)
	if not ok then
		s.dirty = true
		warn(`[Profile] save failed for {player.UserId}: {err}`)
	end
end

function Profile.start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Cfg.Store)
	end)
	if ok then
		store = result
	else
		warn(`[Profile] no DataStore, settings last the session only: {result}`)
	end

	Net.event("SaveSettings").OnServerEvent:Connect(function(player: Player, raw: any)
		local s = sessions[player]
		local now = os.clock()
		if not s or not s.loaded or now - s.lastSave < 1 / Cfg.SaveRate then
			return
		end
		s.lastSave = now
		local clean = R.clean(Cfg.Options :: any, raw, Cfg.MaxKeyName)
		for k, v in clean do
			if s.settings[k] ~= v then
				s.settings[k] = v
				s.dirty = true
			end
		end
	end)

	Players.PlayerAdded:Connect(load)
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		sessions[player] = nil
	end)
	game:BindToClose(function()
		for player in sessions do
			task.spawn(save, player)
		end
		task.wait(Cfg.ShutdownWait) -- (the saves above run meanwhile)
	end)
	task.spawn(function()
		while true do
			task.wait(Cfg.AutosaveEvery)
			for player in sessions do
				task.spawn(save, player)
			end
		end
	end)
end

return Profile
