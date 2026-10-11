--!strict
local U = require("../src/shared/Config/Uniforms")
local Faces = require("../src/shared/Rules/Faces")

return {
	["the face follows health by thirds"] = function()
		assert(Faces.tier(1, U.Faces) == 1, "full health: healthy")
		assert(Faces.tier(0.67, U.Faces) == 1, "67%: healthy")
		assert(Faces.tier(0.66, U.Faces) == 2, "66%: hurt")
		assert(Faces.tier(0.34, U.Faces) == 2, "34%: hurt")
		assert(Faces.tier(0.33, U.Faces) == 3, "33%: wounded")
		assert(Faces.tier(0.01, U.Faces) == 3, "1%: wounded")
	end,
	["dead shows the closed face of the last tier, never one from health 0"] = function()
		local tier, closed = Faces.after(1, 0, 100, U.Faces)
		assert(tier == 1 and closed, "one hit from full health: the healthy closed face")
		tier, closed = Faces.after(2, -20, 100, U.Faces)
		assert(tier == 2 and closed, "killed while hurt: the hurt closed face")
		tier, closed = Faces.after(3, 0, 100, U.Faces)
		assert(tier == 3 and closed, "killed while wounded: the wounded closed face")
	end,
	["alive picks the tier from health and keeps the eyes open"] = function()
		local tier, closed = Faces.after(1, 50, 100, U.Faces)
		assert(tier == 2 and not closed, "50 of 100: hurt, open")
		tier, closed = Faces.after(3, 90, 100, U.Faces)
		assert(tier == 1 and not closed, "healed: back to healthy")
	end,
	["blinks are quick and spread out"] = function()
		local B = U.Blink
		assert(B.Closed > 0.05 and B.Closed < 0.25, "a blink is a short close")
		assert(B.MinGap >= 1 and B.MaxGap > B.MinGap, "blinks are seconds apart")
		assert(Faces.blinkGap(0, B.MinGap, B.MaxGap) == B.MinGap, "gap at its shortest")
		assert(Faces.blinkGap(1, B.MinGap, B.MaxGap) == B.MaxGap, "gap at its longest")
		assert(B.Range > 0, "blink range")
	end,
}
