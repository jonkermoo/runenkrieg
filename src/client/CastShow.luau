--!strict
-- The staff casts in the animation showcase (src/server/Showcase "cast" dummies, Config/Showcase.Casts; DEV place):
-- the server charges each dummy and publishes the cast as attributes; this draws the spell on every client the way
-- others would see a caster (Vfx/Zoltraak at full size, solid, in its kit's team colours): the circles and their orbits open from the staff's
-- head while "CastHeld" is set (counting up while charging), the aiming laser runs ahead while "CastCharging", and a
-- new "CastFire" releases "CastStage" straight ahead (a hip quick fire: opened and released at once). Only near the
-- camera (Config/Vfx.Showcase.Range).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Showcase)
local Spells = require(Shared.Config.Spells)
local SpellRules = require(Shared.Rules.Spells)
local VfxCfg = require(Shared.Config.Vfx)
local Vfx = require(script.Parent.Vfx)

local CastShow = {}

local HOLDS = {}
for i, s in Spells.Stages do
	HOLDS[i] = s.hold
end

local AHEAD = 120 -- how far the laser runs when it points at nothing

local function watch(m: Model)
	local cast: any = nil
	local fired = m:GetAttribute("CastFire") or 0
	-- the dummy's team's magic (Config/Spells.Staff.Teams by its "Kit"), the laser in it
	local schemeName = SpellRules.scheme(m:GetAttribute("Kit"), Spells.Staff.Teams, Spells.Staff.Scheme)
	local function newPointer()
		local s = (VfxCfg.Schemes :: any)[schemeName]
		return Vfx.Pointer.new(s.pointer, s.core)
	end
	local pointer = newPointer()
	m:GetAttributeChangedSignal("Kit"):Connect(function()
		schemeName = SpellRules.scheme(m:GetAttribute("Kit"), Spells.Staff.Teams, Spells.Staff.Scheme)
		pointer.free()
		pointer = newPointer()
	end)
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		if not m.Parent then
			conn:Disconnect()
			pointer.free()
			if cast then
				cast.cancel()
			end
			return
		end
		local tool = m:FindFirstChildOfClass("Tool")
		local muzzle = tool and tool:FindFirstChild("Muzzle", true) :: Attachment?
		local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not muzzle or not root then
			return
		end
		local from = muzzle.WorldPosition
		local tip = CFrame.lookAt(from, from + root.CFrame.LookVector)
		local held = m:GetAttribute("CastHeld")
		local near = (workspace.CurrentCamera.CFrame.Position - from).Magnitude < VfxCfg.Showcase.Range
		if type(held) == "number" then
			if not cast and near then
				cast = Vfx.Zoltraak.begin(tip, HOLDS, schemeName)
			end
			if cast then
				cast.aim(tip)
				cast.update(held)
			end
		end
		if cast and m:GetAttribute("CastCharging") == true then
			local to = Vfx.Util.cast(from, tip.LookVector, AHEAD, { m, Vfx.Util.folder() })
			pointer.set(from, to)
		else
			pointer.hide()
		end
		local f = m:GetAttribute("CastFire") or 0
		if f ~= fired then
			fired = f
			if not cast and near then
				cast = Vfx.Zoltraak.begin(tip, HOLDS, schemeName) -- a hip quick fire: opened and fired at once
			end
			if cast then
				local stage = m:GetAttribute("CastStage")
				cast.release(if type(stage) == "number" then stage else 1, { m, Vfx.Util.folder() })
				cast = nil
			end
		end
	end)
end

function CastShow.start()
	if game.PlaceId ~= Cfg.PlaceId then
		return
	end
	local function folder(f: Instance)
		if f.Name ~= "DevShowcase" then
			return
		end
		local function added(c: Instance)
			if c:IsA("Model") and c:GetAttribute("CastShow") == true then
				watch(c)
			end
		end
		f.ChildAdded:Connect(added)
		for _, c in f:GetChildren() do
			added(c)
		end
	end
	workspace.ChildAdded:Connect(folder)
	local existing = workspace:FindFirstChild("DevShowcase")
	if existing then
		folder(existing)
	end
end

return CastShow
