--!strict
local Cfg = require("../src/shared/Config/Camera")
local Weapons = require("../src/shared/Config/Weapons")
local Camera = require("../src/shared/Rules/Camera")

local S = Cfg.Staff

return {
	["the staff takes the gun's camera and aims in place; guns aim in first person"] = function()
		assert(not Camera.thirdPerson(Cfg.ThirdPersonClasses, "Staff"))
		assert(not Camera.thirdPerson(Cfg.ThirdPersonClasses, "BoltRifle"))
		assert(not Camera.thirdPerson(Cfg.ThirdPersonClasses, nil))
		assert(not Camera.thirdPerson(Cfg.AimInPlace, "BoltRifle"))
		local staffs = 0
		for name, w in Weapons :: any do
			if type(w) == "table" and w.class == "Staff" then
				staffs += 1
				assert(Camera.thirdPerson(Cfg.AimInPlace, w.class), name)
			end
		end
		assert(staffs > 0, "no staff found in Config/Weapons")
	end,
	["the shovel keeps Roblox's camera, out past first person; guns and the staff don't"] = function()
		assert(Camera.thirdPerson(Cfg.FreeClasses, Weapons.shovel.class))
		assert(not Camera.thirdPerson(Cfg.FreeClasses, "BoltRifle"))
		assert(not Camera.thirdPerson(Cfg.FreeClasses, "Staff"))
		assert(Cfg.FreeMinZoom > 0.5 and Cfg.FreeMinZoom < Cfg.FreeMaxZoom)
	end,
	["the gun camera's view: aiming in place stays over the shoulder"] = function()
		assert(Camera.gunView(5, false) == "Third" and Camera.gunView(0, false) == "First")
		assert(Camera.gunView(5, true) == "Aim" and Camera.gunView(0, true) == "Aim")
		assert(Camera.gunView(5, true, true) == "ThirdAim")
		assert(Camera.gunView(0, true, true) == "Aim", "in first person the staff aims in first person")
		assert(Camera.gunTarget(5, true, true) == 5)
		assert(Camera.gunTarget(5, true, false) == 0)
	end,
	["the staff's camera sits closer than the free camera's max, aiming closer still"] = function()
		assert(S.Distance < Cfg.FreeMaxZoom, "the staff's distance must be lower than with nothing drawn")
		assert(S.AimZoom > 0 and S.AimZoom <= S.Distance)
		assert(Camera.target(S, false) == S.Distance)
		assert(Camera.target(S, true) == S.AimZoom)
		assert(S.EyeBlend > 0 and S.EyeBlend <= S.AimZoom)
		assert(S.Fade.near < S.Fade.far and S.Fade.far <= S.AimZoom)
		assert(S.ShoulderVeil > 0 and S.ShoulderVeil < 1, "over the shoulder: see-through, never invisible")
	end,
	["over the shoulder while firing, centred otherwise"] = function()
		assert(Camera.shoulder(S, true, false, math.huge))
		assert(Camera.shoulder(S, false, true, math.huge))
		assert(Camera.shoulder(S, false, false, 0))
		assert(Camera.shoulder(S, false, false, S.ShoulderHold * 0.5))
		assert(not Camera.shoulder(S, false, false, S.ShoulderHold))
		assert(not Camera.shoulder(S, false, false, math.huge))
	end,
	["a gun's wheel steps between first person and the shoulder view, within its range"] = function()
		local G = Cfg.Gun
		assert(G.MinZoom > 0 and G.MinZoom < G.MaxZoom and G.MaxZoom < Cfg.FreeMaxZoom)
		assert(Camera.wheel(G, 0, -1) == G.MinZoom, "out of first person lands at the nearest distance")
		assert(Camera.wheel(G, G.MinZoom, 1) == 0, "one notch in from the nearest is first person")
		assert(Camera.wheel(G, 0, 1) == 0)
		assert(Camera.wheel(G, G.MaxZoom, -1) == G.MaxZoom)
		assert(Camera.wheel(G, G.MinZoom + G.Step, 1) == G.MinZoom)
		assert(Camera.wheel(G, G.MaxZoom, 0) == G.MaxZoom)
		local d = 0
		for _ = 1, 100 do
			d = Camera.wheel(G, d, -1)
		end
		assert(d == G.MaxZoom)
	end,
	["drawing a gun keeps first person, else Roblox's zoom within the range"] = function()
		local G = Cfg.Gun
		assert(Camera.drawn(G, 0.5) == 0)
		assert(Camera.drawn(G, G.FirstBelow) == G.MinZoom)
		assert(Camera.drawn(G, 5) == 5)
		assert(Camera.drawn(G, 100) == G.MaxZoom)
	end,
	["aiming a gun is always first person"] = function()
		assert(Camera.gunTarget(5, true) == 0)
		assert(Camera.gunTarget(5, false) == 5)
		assert(Camera.gunTarget(0, false) == 0)
	end,
	["wrap brings angles into -180..180"] = function()
		assert(Camera.wrap(0) == 0)
		assert(Camera.wrap(190) == -170)
		assert(Camera.wrap(-190) == 170)
		assert(Camera.wrap(720 + 10) == 10)
	end,
	["third person: the head turns first, then the body catches up and settles"] = function()
		local T = Cfg.Turn
		local max = 70
		local t, c = Camera.bodyTarget(0, 40, max, T.Settle, false, false)
		assert(t == 0 and not c, "within the head's reach the body stays")
		t, c = Camera.bodyTarget(0, 80, max, T.Settle, false, false)
		assert(t == 80 and c, "past it the body turns to face the view")
		t, c = Camera.bodyTarget(60, 80, max, T.Settle, false, true)
		assert(t == 80 and c, "and keeps turning until it settles")
		t, c = Camera.bodyTarget(78, 80, max, T.Settle, false, true)
		assert(t == 78 and not c, "settled")
		t, c = Camera.bodyTarget(0, 20, max, T.Settle, true, false)
		assert(t == 20 and c, "firing faces the view")
		t, c = Camera.bodyTarget(0, 20, max, T.Settle, false, false, -90)
		assert(t == -90 and c, "moving faces where it goes, not the view")
		t, c = Camera.bodyTarget(0, 20, max, T.Settle, true, false, -90)
		assert(t == 20, "firing on the move faces the view")
		t, c = Camera.bodyTarget(-90, 20, max, T.Settle, false, true)
		assert(t == 20 and c, "stopped: on to the view")
		t = Camera.bodyTarget(170, -170, max, T.Settle, true, false)
		assert(t == 190, "the short way round, unwrapped near the body")
	end,
	["the spring never jumps or overshoots and arrives"] = function()
		local x, v = 0, 0
		local last = 0
		for _ = 1, 120 do
			x, v = Camera.spring(x, v, 10, Cfg.Gun.Spring, 1 / 60)
			assert(x >= last - 1e-9 and x <= 10 + 1e-9, "monotonic, no overshoot")
			last = x
		end
		assert(math.abs(x - 10) < 0.05, "settles within two seconds")
		local x1 = Camera.spring(0, 0, 10, Cfg.Gun.Spring, 1 / 60)
		assert(x1 < 0.25, "starts gently (no velocity jump)")
		assert(Camera.spring(3, 0, 3, 12, 1 / 60) == 3)
	end,
	["turn rates and the crosshair are sane"] = function()
		local T = Cfg.Turn
		assert(T.Face > 0 and T.Walk > 0)
		assert(T.Settle > 0 and T.Moving > 0 and T.Moving < 1)
		local C = Cfg.Crosshair
		assert(C.Size > C.Thickness * 2 and C.Transparency >= 0 and C.Transparency < 1 and C.Fade > 0)
		assert(C.EdgeShare > 0 and C.EdgeShare <= 1 and C.EdgeWidth >= 0)
	end,
}
