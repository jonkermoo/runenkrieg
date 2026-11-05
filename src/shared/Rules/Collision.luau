--!strict
-- Which collision group a soldier is in, and which soldier groups collide (Config/Collision; src/server/SoldierGroups
-- applies them). Pure: strings and tables only.

local Collision = {}

-- The group for a soldier of kit `kit` (Config/Uniforms.Kits key); `ffa`: a free-for-all match, where everyone is an
-- enemy. No kit, or one not in `kits`: the shared soldiers' group.
function Collision.groupOf(kit: any, ffa: boolean, kits: { [string]: any }, cfg: any): string
	if ffa or type(kit) ~= "string" or kits[kit] == nil then
		return cfg.Soldiers
	end
	return cfg.TeamPrefix .. kit
end

-- Every soldier group: the shared one first, then one per kit (sorted).
function Collision.groups(kits: { [string]: any }, cfg: any): { string }
	local keys = {}
	for k in kits do
		table.insert(keys, k)
	end
	table.sort(keys)
	local out = { cfg.Soldiers }
	for _, k in keys do
		table.insert(out, cfg.TeamPrefix .. k)
	end
	return out
end

-- Whether group `name` holds soldiers.
function Collision.isSoldier(name: string, cfg: any): boolean
	return name == cfg.Soldiers or string.sub(name, 1, #cfg.TeamPrefix) == cfg.TeamPrefix
end

-- Whether soldier groups `a` and `b` collide: everyone but a team's soldiers with each other.
function Collision.collides(a: string, b: string, cfg: any): boolean
	return not (a == b and a ~= cfg.Soldiers)
end

-- Whether the camera's sweep group collides with group `name`, given whether the Default group does
-- (`defaultCollides`): never with soldiers or `cfg.Through`, otherwise as Default.
function Collision.cameraHits(name: string, defaultCollides: boolean, cfg: any): boolean
	if Collision.isSoldier(name, cfg) or table.find(cfg.Through, name) ~= nil then
		return false
	end
	return defaultCollides
end

return Collision
