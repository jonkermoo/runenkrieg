--!strict
local Cfg = require("../src/shared/Config/Boundary")
local B = require("../src/shared/Rules/Boundary")

return {
	["fade: invisible far away, full when close, monotonic"] = function()
		assert(B.fade(Cfg.FadeFar + 1, Cfg.FadeNear, Cfg.FadeFar) == 0)
		assert(B.fade(Cfg.FadeNear, Cfg.FadeNear, Cfg.FadeFar) == 1)
		assert(B.fade(0, Cfg.FadeNear, Cfg.FadeFar) == 1)
		local prev = 1
		for d = Cfg.FadeNear, Cfg.FadeFar, 5 do
			local f = B.fade(d, Cfg.FadeNear, Cfg.FadeFar)
			assert(f <= prev, "fade must not increase with distance")
			prev = f
		end
	end,
	["distanceToPanel clamps to the panel's ends"] = function()
		-- panel at origin spanning x in [-20, 20]
		assert(B.distanceToPanel(0, 10, 0, 0, 1, 0, 40) == 10)
		assert(math.abs(B.distanceToPanel(23, 4, 0, 0, 1, 0, 40) - 5) < 1e-9)
	end,
	["config sane"] = function()
		assert(Cfg.FadeNear < Cfg.FadeFar and Cfg.MaxOpacity > 0 and Cfg.MaxOpacity <= 1)
	end,
}
