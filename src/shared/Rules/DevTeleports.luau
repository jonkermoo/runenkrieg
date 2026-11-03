--!strict
-- Teleport destinations: every sector of the map (in front-line order), every sector of the other frontline maps
-- (`others`: { key, map }, named by their map; user 2026-11-02: Lantern Meadows' teleports), plus Config/DevTools.Extra.

local DevTeleports = {}

export type Dest = {
	id: string,
	name: string,
	x: number,
	z: number,
	y: number?,
	look: { number }?,
	offMap: boolean?,
	map: string?, -- on another generated map (Config/Maps), not Map 1
}

function DevTeleports.list(map: any, cfg: any, others: { { key: string, map: any } }?): { Dest }
	local out: { Dest } = {}
	local function sectors(m: any, key: string?)
		for i, s in m.sectors do
			-- face the next sector along the front (the last one faces back the way it came)
			local nxt = m.sectors[i + 1] or m.sectors[i - 1]
			local name = if s.isHQ then `{s.name} (HQ)` else `{s.id} ({s.startOwner})`
			table.insert(out, {
				id = if key then `{key}_{s.id}` else s.id,
				name = if key then `{m.name}: {name}` else (if s.isHQ then s.name else name),
				x = s.x,
				z = s.z,
				look = { nxt.x, nxt.z },
				map = key,
			})
		end
	end
	sectors(map, nil)
	for _, o in others or {} do
		sectors(o.map, o.key)
	end
	for _, e in cfg.Extra do
		table.insert(out, e)
	end
	return out
end

function DevTeleports.find(map: any, cfg: any, id: string, others: { { key: string, map: any } }?): Dest?
	for _, d in DevTeleports.list(map, cfg, others) do
		if d.id == id then
			return d
		end
	end
	return nil
end

-- Whether a player gets the dev tools: the allowed users always; anyone in a Studio play test or the DEV place only
-- while `open` (the server's mode is one that opens them, Config/Modes; user 2026-10-27: "for any mode thats not the
-- admin mode, make everyone but me [not] have admin privileges"). `open` nil: open.
function DevTeleports.allowed(cfg: any, userId: number, isStudio: boolean, placeId: number?, open: boolean?): boolean
	if table.find(cfg.AllowedUserIds, userId) ~= nil then
		return true
	end
	return open ~= false and ((cfg.AllowInStudio and isStudio) or (cfg.AllowInDevPlace and placeId == cfg.DevPlaceId))
end

return DevTeleports
