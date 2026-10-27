--!strict
-- Teleport destinations: every sector of the map (in front-line order) plus Config/DevTools.Extra.

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

function DevTeleports.list(map: any, cfg: any): { Dest }
	local out: { Dest } = {}
	for i, s in map.sectors do
		-- face the next sector along the front (the last one faces back the way it came)
		local nxt = map.sectors[i + 1] or map.sectors[i - 1]
		table.insert(out, {
			id = s.id,
			name = if s.isHQ then s.name else `{s.id} ({s.startOwner})`,
			x = s.x,
			z = s.z,
			look = { nxt.x, nxt.z },
		})
	end
	for _, e in cfg.Extra do
		table.insert(out, e)
	end
	return out
end

function DevTeleports.find(map: any, cfg: any, id: string): Dest?
	for _, d in DevTeleports.list(map, cfg) do
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
