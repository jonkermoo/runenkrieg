--!strict
-- A whole map loaded on this client (Config/JoinLoading, Rules/JoinLoading; user 2026-11-04: "every map is fully
-- loaded before anyone plays"): on joining (src/client/Menus, behind the Runenkrieg loading screen) and in the armory
-- after a vote (src/client/MatchCutscene, Net "MapLoad"). In turn:
-- 1. the map's model stands in Workspace;
-- 2. every spot of a grid over its bounds, its points and any `extra` spot (the flight's) streamed in, one after
--    another (Player:RequestStreamAroundAsync, each capped at StreamWait; src/server/MapFocus keeps it in after);
-- 3. this client holds the server's count of the map's parts (HeldShare of them, HeldWait at the most);
-- 4. one instance for each mesh, texture and decal asset of the map (and the server's list, `assets`) preloaded,
--    then the download queue empty (DrainWait at the most).
-- Only then is it loaded. The admin's slow load (SlowAttribute on the LocalPlayer) adds seconds to every step.
--   MapLoader.load(key, extra?, assets?) -> State (a running load of the same map is returned; another map's stops)
--   MapLoader.state() -> State?, MapLoader.loaded(key) -> boolean, MapLoader.progress() -> 0..1 (the latest load)
--   MapLoader.forget(), MapLoader.changed: Event (the state moved on)

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.JoinLoading)
local Rules = require(Shared.Rules.JoinLoading)
local LiveMap = require(Shared.LiveMap)

local MapLoader = {}

export type State = {
	key: string,
	stage: string, -- "Map", "Stream", "Parts", "Assets", "Drain", "Done"
	done: number,
	total: number,
	held: number, -- the map's parts this client holds (at the last count)
	parts: number?, -- the server's count
	finished: boolean,
	startedAt: number,
}

local player = Players.LocalPlayer
local current: State? = nil
local finished: { [string]: boolean } = {}
local changedEvent = Instance.new("BindableEvent")
MapLoader.changed = changedEvent.Event

local function slow()
	local s = player:GetAttribute(Cfg.SlowAttribute)
	if type(s) == "number" and s > 0 then
		task.wait(s)
	end
end

local function countHeld(root: Instance?): number
	local n = 0
	for _, d in (if root then root:GetDescendants() else {}) do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function run(this: State, extra: { Vector3 }, assets: { string })
	local function live(): boolean
		return current == this
	end
	local function moved()
		changedEvent:Fire(this)
	end
	local key = this.key
	local ok, map = pcall(LiveMap.get, key)
	if not ok or not map or not map.bounds then
		this.stage, this.finished = "Done", true
		finished[key] = true
		moved()
		return
	end
	-- 1. the map's model
	while not LiveMap.built(key) do
		if not live() then
			return
		end
		task.wait(0.2)
	end
	-- 2. its spots streamed in
	local points = {}
	for _, s in map.sectors or {} do
		table.insert(points, { s.x, s.z })
	end
	for _, v in extra do
		table.insert(points, { v.X, v.Z })
	end
	local spots = Rules.spots(map.bounds, points, Cfg.Spacing)
	this.stage, this.total = "Stream", #spots + 2
	moved()
	for _, p in spots do -- (one after another: the server streams each before the next)
		if not live() then
			return
		end
		slow()
		pcall(function()
			player:RequestStreamAroundAsync(Vector3.new(p[1], 0, p[2]), Cfg.StreamWait)
		end)
		this.done += 1
		moved()
	end
	-- 3. the server's parts held here
	this.stage = "Parts"
	slow()
	local root = workspace:FindFirstChild(key)
	local heldFrom = os.clock()
	while live() do
		local parts = root and root:GetAttribute(Cfg.PartsAttribute)
		this.parts = if type(parts) == "number" then parts else nil
		this.held = countHeld(root)
		moved()
		if Rules.held(this.held, this.parts, Cfg.HeldShare) or os.clock() - heldFrom > Cfg.HeldWait then
			break
		end
		task.wait(0.5)
	end
	if not live() then
		return
	end
	this.done += 1
	-- 4. one instance for each mesh, texture and decal asset (and the server's list: the parts not streamed in too)
	local list: { any } = {}
	local seen: { [string]: boolean } = {}
	local function add(d: Instance, ...: string)
		local new = false
		for _, id in { ... } do
			if id ~= "" and not seen[id] then
				seen[id], new = true, true
			end
		end
		if new then
			table.insert(list, d)
		end
	end
	for _, id in assets do
		if type(id) == "string" and id ~= "" and not seen[id] then
			seen[id] = true
			table.insert(list, id)
		end
	end
	for _, d in (if root then root:GetDescendants() else {}) do
		if d:IsA("MeshPart") then
			add(d, d.MeshId, d.TextureID)
		elseif d:IsA("SpecialMesh") then
			add(d, d.MeshId, d.TextureId)
		elseif d:IsA("Decal") then -- (Textures too)
			add(d, d.Texture)
		elseif d:IsA("SurfaceAppearance") then
			table.insert(list, d)
		end
	end
	this.stage = "Assets"
	this.total = this.done + math.max(#list, 1) + 1
	moved()
	for k = 1, #list, Cfg.Batch do
		if not live() then
			return
		end
		slow()
		pcall(
			ContentProvider.PreloadAsync,
			ContentProvider,
			table.move(list, k, math.min(k + Cfg.Batch - 1, #list), 1, {})
		)
		this.done += math.min(Cfg.Batch, #list - k + 1)
		moved()
	end
	-- 5. nothing of it still downloading
	this.stage = "Drain"
	local drainFrom = os.clock()
	while ContentProvider.RequestQueueSize > 0 and os.clock() - drainFrom < Cfg.DrainWait do
		if not live() then
			return
		end
		task.wait(0.1)
	end
	this.held = countHeld(root)
	this.done, this.stage, this.finished = this.total, "Done", true
	finished[key] = true
	moved()
end

function MapLoader.load(key: string, extra: { Vector3 }?, assets: { string }?): State
	local c = current
	if c and c.key == key then
		return c
	end
	local this: State = {
		key = key,
		stage = "Map",
		done = 0,
		total = 1,
		held = 0,
		parts = nil,
		finished = false,
		startedAt = os.clock(),
	}
	current = this
	finished[key] = nil
	task.spawn(run, this, extra or {}, assets or {})
	return this
end

function MapLoader.state(): State?
	return current
end

function MapLoader.loaded(key: string): boolean
	return finished[key] == true
end

function MapLoader.progress(): number
	local c = current
	if not c then
		return 0
	end
	return if c.finished then 1 else math.min(Rules.progress(c.done, c.total), 0.99)
end

-- A new match's end: the next map's load starts over (what streamed in before stays in).
function MapLoader.forget()
	current = nil
	changedEvent:Fire(nil)
end

-- Yields until map `key` is loaded (started if it isn't loading).
function MapLoader.wait(key: string)
	MapLoader.load(key)
	while not finished[key] do
		task.wait(0.1)
	end
end

return MapLoader
