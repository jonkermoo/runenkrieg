--!strict
-- The map checker's report on Map 1 (roadmap 2.1): `lune run tests/mapreport`. Travel times from each spawn, the
-- sight lines round each sector, pits and cut-off pockets. The pass / fail rules are in tests/mapcheck.spec.luau.
local Check = require("../src/shared/Rules/MapCheck")
local S = require("./mapgrid")

local g, map, M = S.grid, S.map, S.metrics
local walk, sprint = M.Movement.WalkSpeed, M.Movement.SprintSpeed
local range = M.Combat.RifleEffectiveRange

print(`Map checker: {map.name}, {g.nx} x {g.nz} cells of {g.cell} studs`)
local open = 0
for i = 1, g.nx * g.nz do
	if g.open[i] then
		open += 1
	end
end
print(`open cells {open} of {g.nx * g.nz}`)

print("\nTravel (walk / sprint seconds over the ground; straight-line studs)")
for _, team in { "West", "East" } do
	local z = map.spawnZones[team]
	local sx, sz = (z.minX + z.maxX) / 2, (z.minZ + z.maxZ) / 2
	print(`  from the {team} spawn`)
	for _, s in map.sectors do
		local _, d = Check.nearest(g, S.walks[team], s.x, s.z, s.radius)
		local straight = math.sqrt((s.x - sx) ^ 2 + (s.z - sz) ^ 2)
		if d then
			print(
				string.format(
					"    %-4s %6.0f st  %5.1f / %5.1f s  (straight %4.0f)",
					s.id,
					d,
					d / walk,
					d / sprint,
					straight
				)
			)
		else
			print(`    {s.id}  unreachable`)
		end
	end
end

print(`\nSight (a standing soldier seen by one at the sector centre; fog {map.fogEnd}, rifle range {range})`)
for _, s in map.sectors do
	local best, past, all = Check.sightRose(g, s.x, s.z, map.fogEnd, range)
	local sum = 0
	for _, v in all do
		sum += v
	end
	print(
		string.format(
			"  %-4s longest %3.0f, mean %3.0f, %2d of %d directions past %d",
			s.id,
			best,
			sum / #all,
			past,
			#all,
			range
		)
	)
end

for _, team in { "West", "East" } do
	print(`\n{team}: pits {#Check.pits(g, S.spawns[team])}`)
end
local pockets = Check.pockets(g, S.walks.West)
local sizes = {}
for k = 1, math.min(#pockets, 8) do
	local x, z = Check.position(g, pockets[k][1])
	table.insert(sizes, `{#pockets[k]} at ({x}, {z})`)
end
print(`cut-off pockets: {#pockets}; biggest: {table.concat(sizes, ", ")}`)
