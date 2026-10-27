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

function DevTeleports.allowed(cfg: any, userId: number, isStudio: boolean, placeId: number?): boolean
	return (cfg.AllowInStudio and isStudio)
		or (cfg.AllowInDevPlace and placeId == cfg.DevPlaceId)
		or table.find(cfg.AllowedUserIds, userId) ~= nil
end

return DevTeleports
