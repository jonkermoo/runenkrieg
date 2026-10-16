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
	["the staff's zoom range sits inside the free camera's and above first person"] = function()
		assert(S.MaxZoom < Cfg.FreeMaxZoom, "staff max zoom must be lower than with nothing drawn")
		assert(S.MinZoom > 0 and S.MinZoom < S.AimZoom and S.AimZoom <= S.MaxZoom)
		assert(S.Fade.near < S.Fade.far and S.Fade.far <= S.MinZoom + S.Shoulder[1])
	end,
	["drawing: Roblox's zoom clamped into the range, close in stays first person"] = function()
		assert(Camera.start(S, 0.5) == 0)
		assert(Camera.start(S, S.MinZoom) == S.MinZoom)
		assert(Camera.start(S, 4) == math.min(4, S.MaxZoom))
		assert(Camera.start(S, Cfg.FreeMaxZoom) == S.MaxZoom)
	end,
	["the wheel steps, in past the minimum to first person and back out"] = function()
		assert(Camera.zoom(S, S.MaxZoom, -3) == S.MaxZoom, "out stops at the max")
		assert(Camera.zoom(S, S.MaxZoom, 1) == S.MaxZoom - S.ZoomStep)
		assert(Camera.zoom(S, S.MinZoom, 1) == 0, "in past the min: first person")
		assert(Camera.zoom(S, 0, 1) == 0, "in from first person stays")
		assert(Camera.zoom(S, 0, -1) == S.MinZoom, "out of first person lands on the min")
		assert(Camera.zoom(S, 3, 0) == 3)
		local d = S.MaxZoom
		for _ = 1, 50 do
			d = Camera.zoom(S, d, 1)
		end
		assert(d == 0, "scrolling all the way in ends in first person")
	end,
	["aiming comes in, never out; first person stays"] = function()
		assert(Camera.target(S, S.MaxZoom, true) == S.AimZoom)
		assert(Camera.target(S, S.MinZoom, true) == S.MinZoom)
		assert(Camera.target(S, S.MaxZoom, false) == S.MaxZoom)
		assert(Camera.target(S, 0, true) == 0)
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
