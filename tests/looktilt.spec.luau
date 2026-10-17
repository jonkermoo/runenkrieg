--!strict
local L = require("../src/shared/Config/Locomotion")
local T = require("../src/shared/Rules/LookTilt")

local Send = L.LookTilt.Send
local function never()
	return { pitch = math.huge, follow = math.huge, at = -math.huge }
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
		local p, f = T.toSend(31.2, 0.3, never(), 0, Send)
		assert(p == T.quantize(31.2, Send.Step) and f and math.abs(f - 0.3) < 1e-9)
	end,
	["the client sends nothing when the quantized value is unchanged"] = function()
		local last = { pitch = T.quantize(30, Send.Step), follow = 1, at = 0 }
		assert(T.toSend(30 + Send.Step * 0.4, 1, last, 10, Send) == nil)
	end,
	["the client sends no faster than the rate"] = function()
		local last = { pitch = 0, follow = 0, at = 5 }
		assert(T.toSend(40, 1, last, 5 + 0.5 / Send.Rate, Send) == nil)
		assert(T.toSend(40, 1, last, 5 + 1.01 / Send.Rate, Send) ~= nil)
	end,
	["the client clamps before quantizing"] = function()
		local p, f = T.toSend(500, 7, never(), 0, Send)
		assert(p == Send.MaxPitch and f == 1)
	end,
	["the server drops what isn't a number"] = function()
		assert(T.sanitize("10", 1, Send) == nil)
		assert(T.sanitize(10, nil, Send) == nil)
		assert(T.sanitize({}, 1, Send) == nil)
		assert(T.sanitize(0 / 0, 1, Send) == nil)
		assert(T.sanitize(10, 0 / 0, Send) == nil)
	end,
	["the server clamps and quantizes"] = function()
		local p, f = T.sanitize(math.huge, -5, Send)
		assert(p == Send.MaxPitch and f == 0)
		p, f = T.sanitize(-math.huge, 2, Send)
		assert(p == -Send.MaxPitch and f == 1)
		p = T.sanitize(33.3, 0.5, Send)
		assert(p == T.quantize(33.3, Send.Step))
	end,
	["send settings are sane"] = function()
		assert(Send.Rate > 0 and Send.Rate <= 20, "updates per second stay small")
		assert(Send.Step > 0 and Send.Step <= 5, "the pitch step is small enough to look smooth")
		assert(Send.FollowStep > 0 and Send.FollowStep < 1)
		assert(Send.MaxPitch > 0 and Send.MaxPitch <= 90)
		assert(Send.Smoothing > 0)
	end,
	["a stagger leans away from the hit and back"] = function()
		assert(T.stagger(0, 0.3, 14, -1) == 0 and T.stagger(0.3, 0.3, 14, -1) == 0, "nothing at the ends")
		assert(math.abs(T.stagger(0.15, 0.3, 14, -1) - 14) < 1e-9, "shot from the front: back by the full lean midway")
		assert(T.stagger(0.15, 0.3, 14, 1) < 0, "from behind: forward")
		assert(math.abs(T.stagger(0.15, 0.3, 14, 0) - 7) < 1e-9, "from the side: half way back")
		assert(T.stagger(-1, 0.3, 14, -1) == 0 and T.stagger(0.1, 0, 14, -1) == 0)
	end,
}
