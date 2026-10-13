--!strict
-- Dev test caster for the staff spells (Config/Spells.Test; user 2026-10-13), until the staff is a real weapon: in
-- the DEV place, for a player with dev tools and nothing in the hands, left click is the staff. Pressing starts the
-- cast (the first circle opens at once, Vfx/Zoltraak.begin); holding reaches later stages (Rules/Spells: their
-- circles open, larger, further out); the circles follow the aim; release fires the reached stage's beam toward
-- where the camera aims, from where a raised staff's tip would be (Config/Spells.Test.Tip). Visual only, on this
-- client: no damage, nobody else sees it yet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Spells)
local DevTools = require(Shared.Config.DevTools)
local Rules = require(Shared.Rules.Spells)
local Vfx = require(script.Parent.Vfx)

local SpellTest = {}

local AIM_RANGE = 1000 -- how far the aim ray looks for what the crosshair is on
local HOLDS = {}
for i, s in Cfg.Stages do
	HOLDS[i] = s.hold
end

-- The point under the crosshair (screen centre in first person, the mouse otherwise).
local function aimPoint(ignore: { Instance }): Vector3
	local cam = workspace.CurrentCamera
	local m = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(m.X, m.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(ray.Origin, ray.Direction * AIM_RANGE, params)
	return if hit then hit.Position else ray.Origin + ray.Direction * AIM_RANGE
end

-- The staff tip looking at the aim point, or nil (no body).
local function tip(character: Model, ignore: { Instance }): CFrame?
	local torso = character:FindFirstChild("Torso") :: BasePart?
	if not torso then
		return nil
	end
	local t = Cfg.Test.Tip
	local from = (torso.CFrame * CFrame.new(t[1], t[2], t[3])).Position
	local to = aimPoint(ignore)
	if (to - from).Magnitude < 1 then
		return CFrame.lookAt(from, from + torso.CFrame.LookVector)
	end
	return CFrame.lookAt(from, to)
end

function SpellTest.start()
	if game.PlaceId ~= Cfg.Test.PlaceId then
		return
	end
	local player = Players.LocalPlayer
	local held: { cast: any, pressed: number, conn: RBXScriptConnection, ignore: { Instance } }? = nil

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 or held then
			return
		end
		local character = player.Character
		if
			player:GetAttribute(DevTools.Attribute) ~= true
			or not character
			or character:FindFirstChildOfClass("Tool")
		then
			return
		end
		local ignore: { Instance } = { character, Vfx.Util.folder() }
		local t = tip(character, ignore)
		if not t then
			return
		end
		local cast = Vfx.Zoltraak.begin(t, HOLDS)
		local pressed = os.clock()
		local conn = RunService.RenderStepped:Connect(function()
			local now = tip(character, ignore)
			if not now or not character.Parent then
				return
			end
			cast.aim(now)
			cast.update(os.clock() - pressed)
		end)
		held = { cast = cast, pressed = pressed, conn = conn, ignore = ignore }
	end)

	UserInputService.InputEnded:Connect(function(input)
		local h = held
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not h then
			return
		end
		held = nil
		h.conn:Disconnect()
		local stage = Rules.firing(Cfg.Stages, Cfg.Built, os.clock() - h.pressed)
		if stage then
			h.cast.release(stage, h.ignore)
		else
			h.cast.cancel()
		end
	end)

	player.CharacterRemoving:Connect(function()
		local h = held
		if h then
			held = nil
			h.conn:Disconnect()
			h.cast.cancel()
		end
	end)
end

return SpellTest
