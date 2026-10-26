--!strict
-- The staff's mana, quartermaster's brass (Config/Hud.Staff; layout src/shared/ui/CombatHud.json "Staff"; user
-- 2026-10-26: "the staff should be a magic rock of the teams color (faded out if empty, bright if max. flicker while
-- recharging after a stage 3 blast to signify that its no usable)"). Shown while the staff is drawn, in the gun
-- display's place. A brass panel, bottom right, with a magic rock turning in a ViewportFrame: the howitzer's cracked
-- gem (Hud.Staff.model) in the player's team magic colour (Config/Spells.Staff.Teams):
-- - hollow grey and flickering while it recharges (burnt out by a stage 3 shot, Config/Spells.Mana.burnout, or
--   refilling), bright and solid when full (src/client/HudKit.shine, a black outline round it); full again, a white
--   flash;
-- - a shot refused for want of mana: the panel shakes;
-- - full again, it pops (a quick swell and a white flash); otherwise nothing but its brightness says how full it is
--   (user 2026-10-26: "just make the circle have a pop animation once its fully charged. no other indicator").
-- Read from the attributes src/client/StaffAttack writes ("Mana", "ManaLocked", "ManaDenied",
-- "ManaRefilled").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local HudCfg = require(Shared.Config.Hud)
local Palette = require(Shared.Config.Palette)
local Spells = require(Shared.Config.Spells)
local VfxCfg = require(Shared.Config.Vfx)
local SpellRules = require(Shared.Rules.Spells)
local W = require(Shared.Config.Weapons)
local Held = require(script.Parent.Held)
local HudKit = require(script.Parent.HudKit)

local StaffHud = {}

local S = HudCfg.Staff

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

type Rock = { model: Model, parts: { { part: BasePart, rel: CFrame } }, size: Vector3, crystal: HudKit.Crystal }

-- the rock: copies of the gem's parts, centred on the first
local function makeRock(view: ViewportFrame, camera: Camera): Rock?
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	for _, name in S.model do
		f = f and f:FindFirstChild(name)
	end
	local first = f and f:FindFirstChild(S.parts[1], true)
	if not f or not first or not first:IsA("BasePart") then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = "Rock"
	local parts = {}
	for _, name in S.parts do
		local p = (f :: Instance):FindFirstChild(name, true)
		if p and p:IsA("BasePart") then
			local c = p:Clone()
			c:ClearAllChildren()
			c.Anchored = true
			c.Material = Enum.Material.Neon
			c.Parent = model
			table.insert(parts, { part = c, rel = first.CFrame:ToObjectSpace(p.CFrame) })
		end
	end
	model.Parent = view
	-- centred on the gem's own middle (its bounding box), not its pivot
	local centre, size = model:GetBoundingBox()
	for _, q in parts do
		q.rel = centre:ToObjectSpace(first.CFrame * q.rel)
	end
	HudKit.frameBox(
		view,
		camera,
		CFrame.identity,
		Vector3.one * size.Magnitude * S.fit,
		Vector3.zAxis,
		Vector3.yAxis,
		S.fov,
		S.margin
	)
	local list = {}
	for _, q in parts do
		table.insert(list, q.part)
	end
	return { model = model, parts = parts, size = size, crystal = HudKit.crystal(list) }
end

function StaffHud.start()
	local player = Players.LocalPlayer
	local panel = HudKit.panel("Staff", "StaffHud")
	local view = panel.node.StaffView :: ViewportFrame
	local camera = Instance.new("Camera")
	camera.Parent = view
	view.CurrentCamera = camera
	local rock: Rock? = nil
	local home = panel.panel.Position
	local max = Spells.Mana.max
	local angle = 0
	local wasFull, fullAt = true, -math.huge

	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local weapon = character and Held.weapon(character)
		local staff = weapon ~= nil and W[weapon.name] ~= nil and W[weapon.name].class == "Staff"
		panel.gui.Enabled = staff
		if not character or not staff or not weapon then
			return
		end
		if not rock then
			rock = makeRock(view, camera)
		end
		local now = os.clock()
		local value = (character:GetAttribute("Mana") :: number?) or max
		local locked = character:GetAttribute("ManaLocked") == true
		local deniedAt = (character:GetAttribute("ManaDenied") :: number?) or -math.huge
		local refilledAt = (character:GetAttribute("ManaRefilled") :: number?) or -math.huge

		-- a refused shot: a short shake
		local d = now - deniedAt
		local sh = S.shake
		local shake = if d < sh.time then math.sin(d * sh.speed) * sh.size * (1 - d / sh.time) else 0
		panel.panel.Position = home + UDim2.fromOffset(shake, 0)

		local scheme = (VfxCfg.Schemes :: any)[SpellRules.scheme(
			character:GetAttribute("Kit"),
			Spells.Staff.Teams,
			Spells.Staff.Scheme
		)]
		local Magic = Palette.Magic :: any
		local glow, core = rgb(Magic[scheme.glow]), rgb(Magic[scheme.core])

		-- full again: a pop (a quick swell and a white flash); full is the rock at its brightest, nothing else says so
		if value >= max and not wasFull then
			fullAt = now
		end
		wasFull = value >= max
		local r = now - math.max(refilledAt, fullAt)
		local flash = if r < S.flash then 1 - r / S.flash else 0
		local u = (now - fullAt) / S.pop.time
		local swell = if u < 1 then 1 + S.pop.size * math.sin(u * math.pi) * (1 - u) else 1
		camera.FieldOfView = S.fov / swell

		if rock then
			angle += math.rad(S.spin) * dt
			local bob = math.sin(now * S.bob.speed * math.pi * 2) * S.bob.height * rock.size.Magnitude
			local at = CFrame.new(0, bob, 0) * CFrame.Angles(0, angle, 0) * CFrame.Angles(math.rad(S.tilt), 0, 0)
			for _, q in rock.parts do
				q.part.CFrame = at * q.rel
			end
			-- hollow grey and flickering until it's full (burnt out or refilling), then bright, solid and popping
			local full = value >= max and not locked
			HudKit.shine(rock.crystal, full, { glow:Lerp(Color3.new(1, 1, 1), flash), core }, now, camera)
		end
	end)
end

return StaffHud
