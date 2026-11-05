--!strict
-- default.project.json hard-codes StarterPlayer movement; it must match the metrics contract.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Camera = require("../src/shared/Config/Camera")
local M = require("../src/shared/Config/Metrics")
local Load = require("../src/shared/Config/JoinLoading")

local project = serde.decode("json", fs.readFile("default.project.json"))
local props = project.tree.StarterPlayer["$properties"]

return {
	["StarterPlayer movement matches Metrics"] = function()
		assert(props.CharacterWalkSpeed == M.Movement.WalkSpeed, "CharacterWalkSpeed drifted from Metrics")
		assert(props.CharacterJumpHeight == M.Movement.JumpHeight, "CharacterJumpHeight drifted from Metrics")
		assert(props.CharacterMaxSlopeAngle == M.Movement.MaxSlopeAngle, "CharacterMaxSlopeAngle drifted")
		assert(props.CharacterUseJumpPower == false, "must use JumpHeight, not JumpPower")
		-- Roblox's camera (no weapon) zooms out to FreeMaxZoom (user 2026-10-11)
		assert(props.CameraMaxZoomDistance == Camera.FreeMaxZoom, "CameraMaxZoomDistance drifted from Config/Camera")
	end,
	["Rojo never manages Workspace's contents, only its streaming radius"] = function()
		-- (user 2026-11-04: the streaming fix set in code; Workspace holds the maps, so no $path and no children)
		local ws = project.tree.Workspace
		assert(ws ~= nil and ws["$path"] == nil, "Workspace: properties only")
		for k in ws do
			assert(k == "$properties", `Workspace: nothing but $properties ({k})`)
		end
		for k in ws["$properties"] do
			assert(k == "StreamingMinRadius", `Workspace: only the streaming radius ({k})`)
		end
		assert(
			ws["$properties"].StreamingMinRadius == Load.MinRadius,
			"StreamingMinRadius drifted from Config/JoinLoading"
		)
	end,
}
