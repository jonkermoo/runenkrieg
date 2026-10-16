--!strict
local Cfg = require("../src/shared/Config/Camera")
local Weapons = require("../src/shared/Config/Weapons")
local Camera = require("../src/shared/Rules/Camera")

local S = Cfg.Staff

return {
	["only the staff gets the third-person camera"] = function()
		assert(Camera.thirdPerson(Cfg.ThirdPersonClasses, "Staff"))
		assert(not Camera.thirdPerson(Cfg.ThirdPersonClasses, "BoltRifle"))
		assert(not Camera.thirdPerson(Cfg.ThirdPersonClasses, nil))
		local staffs = 0
		for name, w in Weapons :: any do
			if type(w) == "table" and w.class == "Staff" then
				staffs += 1
				assert(Camera.thirdPerson(Cfg.ThirdPersonClasses, w.class), name)
			end
		end
		assert(staffs > 0, "no staff found in Config/Weapons")
	end,
	["the staff's camera sits closer than the free camera's max, aiming closer still"] = function()
		assert(S.Distance < Cfg.FreeMaxZoom, "the staff's distance must be lower than with nothing drawn")
		assert(S.AimZoom > 0 and S.AimZoom <= S.Distance)
		assert(Camera.target(S, false) == S.Distance)
		assert(Camera.target(S, true) == S.AimZoom)
		assert(S.EyeBlend > 0 and S.EyeBlend <= S.AimZoom)
		assert(S.Fade.near < S.Fade.far and S.Fade.far <= S.AimZoom)
	end,
	["over the shoulder while firing, centred otherwise"] = function()
		assert(Camera.shoulder(S, true, false, math.huge))
		assert(Camera.shoulder(S, false, true, math.huge))
		assert(Camera.shoulder(S, false, false, 0))
		assert(Camera.shoulder(S, false, false, S.ShoulderHold * 0.5))
		assert(not Camera.shoulder(S, false, false, S.ShoulderHold))
		assert(not Camera.shoulder(S, false, false, math.huge))
	end,
}
