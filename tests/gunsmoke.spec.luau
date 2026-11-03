--!strict
local Cfg = require("../src/shared/Config/Vfx")
local R = require("../src/shared/Rules/Gunsmoke")

local H = Cfg.Gunsmoke.Haze

return {
	["the machine gun's heat builds a shot at a time and cools"] = function()
		assert(R.heat(0, 0, 1, H.decay, H.cap) == 1)
		assert(R.heat(2, 1, 0, 4, H.cap) == 0, "never below cold")
		assert(R.heat(H.cap, 0, 5, H.decay, H.cap) == H.cap, "capped")
		-- held at 450 a minute (7.5 a second) it outruns the cooling: full haze in about 5 s
		local h = 0
		for _ = 1, 40 do
			h = R.heat(h, 1 / 7.5, 1, H.decay, H.cap)
		end
		assert(h >= H.full, "a long burst reaches full haze: " .. h)
		-- a short burst of 3 never hazes
		h = 0
		for _ = 1, 3 do
			h = R.heat(h, 1 / 7.5, 1, H.decay, H.cap)
		end
		assert(R.haze(h, H.start, H.full, H.rate) == 0)
	end,
	["the haze grows from start to full heat"] = function()
		assert(R.haze(0, H.start, H.full, H.rate) == 0)
		assert(R.haze(H.full, H.start, H.full, H.rate) == H.rate)
		assert(R.haze(H.cap, H.start, H.full, H.rate) == H.rate)
		local mid = R.haze((H.start + H.full) / 2, H.start, H.full, H.rate)
		assert(math.abs(mid - H.rate / 2) < 1e-9)
		assert(R.haze(5, 5, 5, 3) == 3 and R.haze(4, 5, 5, 3) == 0)
	end,
}
