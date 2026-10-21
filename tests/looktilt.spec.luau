--!strict
local C = require("../src/shared/Config/Camera")
local L = require("../src/shared/Config/Locomotion")
local T = require("../src/shared/Rules/LookTilt")

local Send = L.LookTilt.Send
local A = C.Aim3P
local Max = A.Max
local function never()
	return { pitch = math.huge, follow = math.huge, aimYaw = math.huge, aimPitch = math.huge, at = -math.huge }
end
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

return {
	["quantize rounds to the nearest step"] = function()
		assert(T.quantize(0, 2) == 0)
		assert(T.quantize(2.9, 2) == 2)
		assert(T.quantize(3.1, 2) == 4)
		assert(T.quantize(-3.1, 2) == -4)
		assert(math.abs(T.quantize(0.34, 0.1) - 0.3) < 1e-9)
	end,
	["the torso takes a share of the pitch, capped both ways"] = function()
		assert(T.torso(0, 0.28, 13) == 0)
		assert(math.abs(T.torso(10, 0.28, 13) - 2.8) < 1e-9)
		assert(T.torso(89, 0.28, 13) == 13)
		assert(T.torso(-89, 0.28, 13) == -13)
	end,
	["the gun turns by the rest of the pitch it follows"] = function()
		assert(math.abs(T.weaponTurn(40, 1, 11.2) - 28.8) < 1e-9)
		assert(T.weaponTurn(40, 0, 11.2) == -11.2) -- no follow: the arms hold against the torso's tilt
		assert(T.weaponTurn(0, 1, 0) == 0)
	end,
	["ease is a share between 0 and 1"] = function()
		assert(T.ease(10, 0) == 0)
		local k = T.ease(10, 1 / 60)
		assert(k > 0 and k < 1)
		assert(T.ease(10, 100) <= 1)
	end,
	["the client sends a change, quantized"] = function()
		local p, f = T.toSend(31.2, 0.3, 0, 0, never(), 0, Send, Max)
		assert(p == T.quantize(31.2, Send.Step) and f and math.abs(f - 0.3) < 1e-9)
	end,
	["the client sends nothing when the quantized value is unchanged"] = function()
		local last = { pitch = T.quantize(30, Send.Step), follow = 1, aimYaw = 0, aimPitch = 0, at = 0 }
		assert(T.toSend(30 + Send.Step * 0.4, 1, 0.2, -0.3, last, 10, Send, Max) == nil)
	end,
	["the client sends no faster than the rate"] = function()
		local last = { pitch = 0, follow = 0, aimYaw = 0, aimPitch = 0, at = 5 }
		assert(T.toSend(40, 1, 0, 0, last, 5 + 0.5 / Send.Rate, Send, Max) == nil)
		assert(T.toSend(40, 1, 0, 0, last, 5 + 1.01 / Send.Rate, Send, Max) ~= nil)
	end,
	["the client clamps before quantizing"] = function()
		local p, f, ay, ap = T.toSend(500, 7, 1e9, -1e9, never(), 0, Send, Max)
		assert(p == Send.MaxPitch and f == 1)
		assert(ay == T.quantize(Max.yaw, Send.AimStep) and ap == T.quantize(-Max.pitch, Send.AimStep))
	end,
	["the server drops what isn't a number"] = function()
		assert(T.sanitize("10", 1, 0, 0, Send, Max) == nil)
		assert(T.sanitize(10, nil, 0, 0, Send, Max) == nil)
		assert(T.sanitize({}, 1, 0, 0, Send, Max) == nil)
		assert(T.sanitize(0 / 0, 1, 0, 0, Send, Max) == nil)
		assert(T.sanitize(10, 0 / 0, 0, 0, Send, Max) == nil)
	end,
	["the server clamps and quantizes"] = function()
		local p, f = T.sanitize(math.huge, -5, 0, 0, Send, Max)
		assert(p == Send.MaxPitch and f == 0)
		p, f = T.sanitize(-math.huge, 2, 0, 0, Send, Max)
		assert(p == -Send.MaxPitch and f == 1)
		p = T.sanitize(33.3, 0.5, 0, 0, Send, Max)
		assert(p == T.quantize(33.3, Send.Step))
	end,
	["a change in the turn onto the crosshair alone is sent"] = function()
		local last = { pitch = 0, follow = 1, aimYaw = 0, aimPitch = 0, at = 0 }
		local p, f, ay, ap = T.toSend(0, 1, 5.2, 0, last, 10, Send, Max)
		assert(p == 0 and f == 1 and ay == T.quantize(5.2, Send.AimStep) and ap == 0)
	end,
	["the server clamps the turn onto the crosshair and zeroes junk"] = function()
		local p, f, ay, ap = T.sanitize(10, 1, 1e9, -1e9, Send, Max)
		assert(p and f)
		assert(ay == T.quantize(Max.yaw, Send.AimStep) and ap == T.quantize(-Max.pitch, Send.AimStep))
		p, f, ay, ap = T.sanitize(10, 1, "x", 0 / 0, Send, Max)
		assert(p and f and ay == 0 and ap == 0, "an older or broken payload still poses the pitch")
	end,
	["angles of a direction: yaw + left of -Z, pitch + up"] = function()
		local y, p = T.angles(0, 0, -1)
		assert(near(y, 0) and near(p, 0))
		y, p = T.angles(-1, 0, 0)
		assert(near(y, 90) and near(p, 0), "to the left")
		y, p = T.angles(0, 1, -1)
		assert(near(y, 0) and near(p, 45))
		y, p = T.angles(0, 0, 0)
		assert(y == 0 and p == 0, "no direction: none")
	end,
	["the turn onto the crosshair is the difference, the short way, capped"] = function()
		local y, p = T.aimTurn(2, -3, 7, 1, Max)
		assert(near(y, 5) and near(p, 4))
		y = T.aimTurn(175, 0, -175, 0, Max)
		assert(near(y, 10), "across the back the short way")
		y, p = T.aimTurn(0, 0, 80, -80, Max)
		assert(y == Max.yaw and p == -Max.pitch)
	end,
	["the average pointing settles the short way round"] = function()
		assert(near(T.settle(10, 20, 0.5), 15))
		assert(near(T.wrap(T.settle(170, -170, 0.5)), -180), "through 180, not back through 0")
		assert(T.settle(10, 20, 0) == 10 and T.settle(10, 20, 1) == 20)
	end,
	["the crosshair's point: what it hits, else the fallback, never at the muzzle"] = function()
		assert(T.aimDistance(40, 5, A.Fallback, A.MinDistance) == 40)
		assert(T.aimDistance(nil, 5, A.Fallback, A.MinDistance) == A.Fallback)
		assert(T.aimDistance(6, 5, A.Fallback, A.MinDistance) == 5 + A.MinDistance)
	end,
	["aim settings are sane"] = function()
		assert(A.Fallback > 100 and A.MinDistance > 0 and A.MinDistance < 20)
		assert(Max.yaw > 0 and Max.yaw <= 45 and Max.pitch > 0 and Max.pitch <= 45, "a small correction")
		assert(A.Settle > 0 and A.Settle < 6, "slow enough that the animation's motion still shows")
		assert(A.Ease > 0 and A.DistanceEase > 0)
		assert(A.Modes.Third and not (A.Modes :: any).First and not (A.Modes :: any).Aim, "never in first person")
		assert(A.States.ready == 1 and A.States.carry == 0)
		assert(Send.AimStep > 0 and Send.AimStep <= 2)
	end,
	["send settings are sane"] = function()
		assert(Send.Rate > 0 and Send.Rate <= 20, "updates per second stay small")
		assert(Send.Step > 0 and Send.Step <= 5, "the pitch step is small enough to look smooth")
		assert(Send.FollowStep > 0 and Send.FollowStep < 1)
		assert(Send.MaxPitch > 0 and Send.MaxPitch <= 90)
		assert(Send.Smoothing > 0)
	end,
	["the head turns toward the look, capped with the animation's glance"] = function()
		local max = L.LookTilt.Head.Max
		assert(T.headYaw(30, 0, 0, max, L.LookTilt.Head.Behind) == 30)
		assert(T.headYaw(-30, 0, 0, max, L.LookTilt.Head.Behind) == -30)
		assert(T.headYaw(100, 0, 0, max, L.LookTilt.Head.Behind) == max)
		assert(T.headYaw(-100, 0, 0, max, L.LookTilt.Head.Behind) == -max)
		assert(
			T.headYaw(60, 20, 0, max, L.LookTilt.Head.Behind) == max - 20,
			"the glance and the turn together stay within the limit"
		)
		assert(T.headYaw(-60, -20, 0, max, L.LookTilt.Head.Behind) == -max + 20)
		assert(T.headYaw(360 + 30, 0, 0, max, L.LookTilt.Head.Behind) == 30, "wrapped")
	end,
	["looking round behind, the head stays on its side"] = function()
		local max = L.LookTilt.Head.Max
		assert(T.headYaw(-170, 0, max, max, L.LookTilt.Head.Behind) == max, "past behind from the left: stays left")
		assert(T.headYaw(170, 0, -max, max, L.LookTilt.Head.Behind) == -max)
		assert(T.headYaw(80, 0, -10, max, L.LookTilt.Head.Behind) == max, "under 90 it may cross")
	end,
	["the head turn sent is throttled, quantized and only on change"] = function()
		local H = L.LookTilt.Head
		local max = H.Max
		local y = T.yawToSend(31.4, { yaw = math.huge, at = -math.huge }, 0, H.Send, max)
		assert(y == T.quantize(31.4, H.Send.Step))
		assert(T.yawToSend(31.4, { yaw = y :: number, at = -math.huge }, 0, H.Send, max) == nil)
		assert(T.yawToSend(50, { yaw = 0, at = 0 }, 1 / H.Send.Rate / 2, H.Send, max) == nil)
		assert(T.yawToSend(500, { yaw = 0, at = -math.huge }, 0, H.Send, max) == T.quantize(max, H.Send.Step))
	end,
	["the server clamps a head turn and drops junk"] = function()
		local H = L.LookTilt.Head
		assert(T.sanitizeYaw("x", H.Send.Step, H.Max) == nil)
		assert(T.sanitizeYaw(0 / 0, H.Send.Step, H.Max) == nil)
		assert(T.sanitizeYaw(1e9, H.Send.Step, H.Max) == T.quantize(H.Max, H.Send.Step))
		assert(T.sanitizeYaw(-1e9, H.Send.Step, H.Max) == T.quantize(-H.Max, H.Send.Step))
		assert(T.inRange(H.Send.Range, H.Send.Range) and not T.inRange(H.Send.Range + 1, H.Send.Range))
		assert(H.Max > 0 and H.Max < 90, "a realistic neck")
	end,
}
