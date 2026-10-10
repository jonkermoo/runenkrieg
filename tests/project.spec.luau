--!strict
-- default.project.json hard-codes StarterPlayer movement; it must match the metrics contract.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local M = require("../src/shared/Config/Metrics")

local project = serde.decode("json", fs.readFile("default.project.json"))
local props = project.tree.StarterPlayer["$properties"]

return {
	["StarterPlayer movement matches Metrics"] = function()
		assert(props.CharacterWalkSpeed == M.Movement.WalkSpeed, "CharacterWalkSpeed drifted from Metrics")
		assert(props.CharacterJumpHeight == M.Movement.JumpHeight, "CharacterJumpHeight drifted from Metrics")
		assert(props.CharacterMaxSlopeAngle == M.Movement.MaxSlopeAngle, "CharacterMaxSlopeAngle drifted")
		assert(props.CharacterUseJumpPower == false, "must use JumpHeight, not JumpPower")
	end,
	["Rojo never manages Workspace"] = function()
		assert(project.tree.Workspace == nil, "Workspace holds maps; Rojo must not own it")
	end,
}
