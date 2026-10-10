--!strict
-- Design invariants: if a metric change breaks one of these, the maps and characters drift apart.
local M = require("../src/shared/Config/Metrics")

local function hopApex(): number
	return M.Movement.JumpHeight
end

return {
	["full cover hides a standing soldier"] = function()
		assert(M.Cover.FullCoverMin > M.Character.Height, "full cover must be taller than the character")
	end,
	["trench hides a standing soldier on the floor"] = function()
		assert(M.Trench.Depth >= M.Cover.FullCoverMin, "trench must be full cover")
	end,
	["on the firestep the aimed muzzle clears the parapet"] = function()
		local muzzle = M.Trench.FirestepHeight + M.Character.AimMuzzleHeight
		assert(muzzle >= M.Trench.Depth + 0.3, "rifle would fire into the parapet from the firestep")
	end,
	["firestep can be hopped onto"] = function()
		assert(M.Trench.FirestepHeight <= M.Cover.HopableLedgeMax, "firestep too tall to hop onto")
	end,
	["a hop cannot escape a trench (exits are needed)"] = function()
		assert(hopApex() < M.Trench.Depth - M.Trench.FirestepHeight, "player could hop out from the firestep")
	end,
	["hopable ledges are actually hopable"] = function()
		assert(M.Cover.HopableLedgeMax < hopApex(), "hopable ledge exceeds jump height")
	end,
	["low cover cannot be hopped"] = function()
		assert(M.Cover.LowCoverMin > hopApex(), "low cover must block a hop")
	end,
	["doors fit a soldier"] = function()
		assert(M.Building.DoorWidth > M.Character.Width, "door narrower than character")
		assert(M.Building.DoorHeight > M.Character.Height + 1, "door too low")
	end,
	["trench floor fits two soldiers passing shoulder to shoulder"] = function()
		assert(M.Trench.FloorWidth >= M.Character.ShoulderWidth * 2 + 1, "trench too narrow to pass")
	end,
	["stairs are climbable"] = function()
		assert(M.Building.StairRise < M.Character.HipHeight / 2, "stair rise too tall for auto step-up")
		local angle = math.deg(math.atan(M.Building.StairRise / M.Building.StairRun))
		assert(angle < M.Movement.MaxSlopeAngle, "stair pitch exceeds max slope")
	end,
	["sprint is faster than walk is faster than aim-walk"] = function()
		assert(M.Movement.SprintSpeed > M.Movement.WalkSpeed and M.Movement.WalkSpeed > M.Movement.AimWalkSpeed)
	end,
	["rifle range fits inside fog"] = function()
		assert(M.Combat.RifleEffectiveRange < M.Combat.FogEnd, "can shoot further than you can see")
	end,
	["capture zones do not overlap"] = function()
		assert(M.Sector.CaptureRadius * 2 < M.Sector.Spacing, "adjacent capture zones overlap")
	end,
}
