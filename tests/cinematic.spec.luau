--!strict
local C = require("../src/shared/Config/Cinematic")
local R = require("../src/shared/Rules/Cinematic")

return {
	["the focus eases toward the target and never overshoots"] = function()
		assert(R.focus(10, 100, 6, 0) == 10)
		assert(R.focus(10, 10, 6, 1) == 10)
		local f = R.focus(10, 100, 6, 1 / 30)
		assert(f > 10 and f < 100)
		assert(R.focus(10, 100, 6, 100) <= 100)
		assert(R.focus(100, 10, 6, -1) == 100)
	end,
	["the in-focus radius is a share of the focus, with a floor and a cap"] = function()
		assert(R.radius(80, 0.5, 30, 50) == 40)
		assert(R.radius(10, 0.5, 30, 50) == 30)
		assert(R.radius(0, 0.5, 30, 50) == 30)
		assert(R.radius(200, 0.5, 30, 50) == 50)
	end,
	["the numbers are within Roblox's limits"] = function()
		assert(C.Dof.far >= 0 and C.Dof.far <= 1)
		assert(C.Dof.minRadius > 0 and C.Dof.minRadius <= C.Focus.maxRadius)
		assert(C.Focus.maxDistance <= 200 and C.Focus.maxRadius <= 50)
		assert(C.AimFarShare >= 0 and C.AimFarShare <= 1)
		local v = C.Vignette
		assert(v.size > 0 and v.size < 0.5)
		assert(v.transparency >= 0 and v.transparency <= 1)
		for _, c in v.color do
			assert(c >= 0 and c <= 255)
		end
	end,
}
