--!strict
local C = require("../src/shared/Config/Build")
local Palette = require("../src/shared/Config/Palette")
local A = require("../src/shared/Config/Artillery")
local S = require("../src/shared/Rules/Scaffold")

return {
	["every gun has a building site, each piece sized, coloured and not zero long"] = function()
		for key in A.Guns do
			local spec = C.Scaffold[key]
			assert(spec, key)
			local pieces = S.pieces(spec, C.Scaffold.Sizes)
			assert(#pieces >= 6, key)
			for _, p in pieces do
				assert(p.w > 0 and p.h > 0, key)
				assert(Palette.Build.Scaffold[p.color], p.color)
				local d = math.abs(p.a[1] - p.b[1]) + math.abs(p.a[2] - p.b[2]) + math.abs(p.a[3] - p.b[3])
				assert(d > 0.01, key)
				-- an upright piece names a sideways top (CFrame.lookAt needs one)
				local up = math.abs(p.a[2] - p.b[2]) / d > 0.99
				assert(not up or p.up[2] == 0, key)
			end
		end
	end,
	["the tripod's poles meet over its centre, its feet on the floor"] = function()
		local t = { x = 0, z = -1, height = 7, spread = 3.6, turn = 90, hook = 3.9 }
		local pieces = S.pieces({ tripod = t }, C.Scaffold.Sizes)
		for k = 1, 3 do
			local p = pieces[k]
			assert(p.a[2] == 0, "foot")
			assert(p.b[2] > t.height and math.abs(p.b[1] - t.x) < 0.5 and math.abs(p.b[3] - t.z) < 0.5, "top")
		end
	end,
	["the howitzer's scaffold stays inside its pit's floor"] = function()
		local f = C.Scaffold.artillery_howitzer.frame
		local r = A.Guns.artillery_howitzer.dig.radius
		local corner = math.sqrt((math.abs(f.x) + f.width / 2) ^ 2 + (math.abs(f.z) + f.depth / 2) ^ 2)
		assert(corner < r, `corner {corner} past the floor {r}`)
	end,
}
