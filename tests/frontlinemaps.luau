--!strict
-- The frontline maps every shared map spec runs over (sectors, village, map checker; docs/maps/MAP_RULES.md §5), and a
-- helper that builds one spec's tests per map, each named "[<map>] <test>".
local NAMES = { "Map1", "LanternMeadows" }

local maps = {}
for _, name in NAMES do
	table.insert(maps, { name = name, map = (require :: any)(`../src/shared/Config/Maps/{name}`) })
end

local function each(build: (map: any, name: string) -> { [string]: () -> () }): { [string]: () -> () }
	local out = {}
	for _, m in maps do
		for test, fn in build(m.map, m.name) do
			out[`[{m.name}] {test}`] = fn
		end
	end
	return out
end

return { names = NAMES, maps = maps, each = each }
