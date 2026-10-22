--!strict
local T = require("../src/shared/Rules/Teams")
local U = require("../src/shared/Config/Uniforms")

return {
	["the same kit is the same team"] = function()
		for _, kit in U.Teams do
			assert(T.same(kit, kit), `{kit} with {kit}`)
		end
	end,
	["different kits are enemies"] = function()
		for _, a in U.Teams do
			for _, b in U.Teams do
				if a ~= b then
					assert(not T.same(a, b), `{a} with {b}`)
				end
			end
		end
	end,
	["an unknown kit is nobody's teammate"] = function()
		assert(not T.same(nil, nil), "both unknown")
		assert(not T.same(nil, "uniform1"), "one unknown")
		assert(not T.same("uniform1", nil), "the other unknown")
		assert(not T.same("", ""), "empty")
		assert(not T.same(1, 1), "not a kit name")
	end,
}
