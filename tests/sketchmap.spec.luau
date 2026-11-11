--!strict
-- The sketch map's frame (Config/SketchMap.Maps): every point with its whole seal inside the drawn area, on every
-- frontline map (user 2026-11-10: "HQ is off the map", the deploy map of the reworked Lantern Meadows).
local Cfg = require("../src/shared/Config/SketchMap") :: any
local Maps = require("./frontlinemaps")

return Maps.each(function(map: any, name: string)
	return {
		["every point's seal sits inside the sketch map's frame"] = function()
			local m = Cfg.Maps[name]
			assert(m, `no sketch map for {name}`)
			local wide = m.x[2] - m.x[1]
			local tall = m.z[2] - m.z[1]
			local aspect = (m.size[1] - 2 * m.pad) / (m.size[2] - 2 * m.pad)
			assert(math.abs(wide / tall - aspect) < 0.05 * aspect, `{name}'s frame isn't the image's shape`)
			for _, s in map.sectors do
				local r = (if s.isHQ then Cfg.Point.hqRadius else Cfg.Point.radius) * wide
				assert(s.x - r >= m.x[1] and s.x + r <= m.x[2], `{s.id} at x {s.x} is off {name}'s sketch map`)
				assert(s.z - r >= m.z[1] and s.z + r <= m.z[2], `{s.id} at z {s.z} is off {name}'s sketch map`)
			end
		end,
	}
end)
