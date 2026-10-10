--!strict
-- Layout invariants for Map 1 against the metrics contract.
local M = require("../src/shared/Config/Metrics")
local Map1 = require("../src/shared/Config/Maps/Map1")

local sectors = Map1.sectors

local function dist(a, b): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

return {
	["chain is HQ, 5 sectors, HQ"] = function()
		assert(#sectors == 7, "expected 7 entries")
		assert(sectors[1].isHQ and sectors[#sectors].isHQ, "chain must start and end with an HQ")
	end,
	["exactly one neutral sector, in the center"] = function()
		local neutral = {}
		for i, s in sectors do
			if s.startOwner == "Neutral" then
				table.insert(neutral, i)
			end
		end
		assert(#neutral == 1 and neutral[1] == 4, "the center sector must be the only neutral one")
	end,
	["start ownership is symmetric"] = function()
		for i = 1, 3 do
			assert(sectors[i].startOwner == "West", `{sectors[i].id} should start West`)
			assert(sectors[#sectors + 1 - i].startOwner == "East", `{sectors[#sectors + 1 - i].id} should start East`)
		end
	end,
	["sector spacing within 15% of the metric"] = function()
		for i = 1, #sectors - 1 do
			local d = dist(sectors[i], sectors[i + 1])
			local target = M.Sector.Spacing
			assert(math.abs(d - target) / target <= 0.15, `{sectors[i].id}->{sectors[i + 1].id} is {d}`)
		end
	end,
	["capture zones never overlap"] = function()
		for i = 1, #sectors - 1 do
			local a, b = sectors[i], sectors[i + 1]
			assert(dist(a, b) > a.radius + b.radius, `{a.id} and {b.id} overlap`)
		end
	end,
	["sectors sit inside the playable bounds"] = function()
		local b = Map1.bounds
		for _, s in sectors do
			assert(s.x - s.radius >= b.minX and s.x + s.radius <= b.maxX, `{s.id} out of X bounds`)
			assert(s.z - s.radius >= b.minZ and s.z + s.radius <= b.maxZ, `{s.id} out of Z bounds`)
		end
	end,
	["river lies between the S3 and S4 zones"] = function()
		local s3, s4 = sectors[4], sectors[5]
		local r = Map1.river
		local reach = r.width / 2 + r.bankWidth + r.meanderAmp
		assert(s3.x + s3.radius < r.x - reach, "river cuts into S3")
		assert(s4.x - s4.radius > r.x + reach, "river cuts into S4")
	end,
	["river has a vehicle-width ford and infantry alternatives"] = function()
		local wide, narrow = 0, 0
		for _, f in Map1.river.fords do
			assert(f.width > M.Character.Width, "ford too narrow for a soldier")
			if f.width >= 16 then
				wide += 1
			else
				narrow += 1
			end
		end
		assert(wide >= 1 and narrow >= 2, "need 1+ vehicle ford and 2+ infantry fords")
	end,
	["map fits the fog: you cannot see HQ to HQ"] = function()
		assert(dist(sectors[1], sectors[#sectors]) > Map1.fogEnd * 2, "map too small for its fog")
	end,
}
