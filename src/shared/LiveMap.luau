--!strict
-- The map the Normal match is on (user 2026-11-02: a map vote between matches, src/server/MapVote). Workspace's
-- Config/Frontline.MapAttribute names it (a key of Config/Maps; set by src/server/Frontline), Config/Frontline.MapKey
-- until then. Modules that play on the match's map read `LiveMap.map`, a stand-in for that map's config: every field
-- read goes to the live map's, so it follows a switch without anyone requiring again.
--   LiveMap.key() -> string, LiveMap.get(key?) -> config, LiveMap.map, LiveMap.frontline() -> { key } (every map in
--   Config/Maps with a sector chain and both spawn zones, sorted), LiveMap.built(key) -> boolean (its model stands in
--   Workspace: src/dev/Greybox names it by key).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Frontline)
local MapsFolder = Shared.Config:WaitForChild("Maps")

local LiveMap = {}

local loaded: { [string]: any } = {}

function LiveMap.get(key: string?): any
	local k = key or LiveMap.key()
	local m = loaded[k]
	if not m then
		local module = MapsFolder:FindFirstChild(k)
		assert(module and module:IsA("ModuleScript"), `[LiveMap] no map "{k}" in Config/Maps`)
		m = require(module) :: any
		loaded[k] = m
	end
	return m
end

function LiveMap.key(): string
	local k = workspace:GetAttribute(Cfg.MapAttribute)
	if type(k) == "string" and MapsFolder:FindFirstChild(k) then
		return k
	end
	return Cfg.MapKey
end

function LiveMap.frontline(): { string }
	local out = {}
	for _, module in MapsFolder:GetChildren() do
		if module:IsA("ModuleScript") then
			local ok, m = pcall(require, module)
			local spawns = ok and type(m) == "table" and (m :: any).spawnZones
			if type(spawns) == "table" and spawns.West and spawns.East and #((m :: any).sectors or {}) > 1 then
				table.insert(out, module.Name)
			end
		end
	end
	table.sort(out)
	return out
end

function LiveMap.built(key: string): boolean
	return workspace:FindFirstChild(key) ~= nil
end

LiveMap.map = setmetatable({}, {
	__index = function(_, field)
		return LiveMap.get()[field]
	end,
}) :: any

return LiveMap
