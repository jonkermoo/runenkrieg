--!strict
-- The staff's mana, quartermaster's brass (Config/Hud.Staff; layout src/shared/ui/CombatHud.json "Staff"; user
-- 2026-10-26: "the staff should be a magic rock of the teams color (faded out if empty, bright if max. flicker while
-- recharging after a stage 3 blast to signify that its no usable)"). Shown while the staff is drawn, in the gun
-- display's place. A brass panel, bottom right, with a magic rock turning in a ViewportFrame: the howitzer's cracked
-- gem (Hud.Staff.model) in the player's team magic colour (Config/Spells.Staff.Teams):
-- - as bright as the mana is full: faded and see-through when empty, solid and glowing when full;
-- - burnt out by a stage 3 shot (Config/Spells.Mana.burnout): it flickers, dropping out, until it's usable again;
--   full again, a white flash;
-- - a shot refused for want of mana: the panel shakes;
-- - three lamps under it, Zoltraak's stages: dimly lit while the mana could pay for that stage, bright as a held charge
--   reaches it (the reached one pulsing).
-- Read from the attributes src/client/StaffAttack writes ("Mana", "ManaLocked", "ManaCost", "ManaDenied",
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

type Rock = { model: Model, parts: { { part: BasePart, rel: CFrame } }, size: Vector3 }

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
	local size = first.Size
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
	return { model = model, parts = parts, size = size }
end

function StaffHud.start()
	local player = Players.LocalPlayer
	local UI = Palette.UI.Hud :: any
	local panel = HudKit.panel("Staff", "StaffHud")
	local view = panel.node.StaffView :: ViewportFrame
	local camera = Instance.new("Camera")
	camera.Parent = view
	view.CurrentCamera = camera
	local rock: Rock? = nil
	local home = panel.panel.Position
	local lamps = { panel.node.Lamp1, panel.node.Lamp2, panel.node.Lamp3 }
	local max = Spells.Mana.max
	local costs = Spells.Mana.cost
	local flickerUntil, nextFlicker = 0, 0
	local rng = Random.new()
	local angle = 0

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
		panel.set("staff", W[weapon.name].display)
		local now = os.clock()
		local value = (character:GetAttribute("Mana") :: number?) or max
		local locked = character:GetAttribute("ManaLocked") == true
		local cost = character:GetAttribute("ManaCost") :: number?
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
		local empty = rgb(UI.rockEmpty)
		local share = math.clamp(value / max, 0, 1)

		-- burnt out: drop-outs at random, the glow down to a share while one lasts
		local bright = share
		if locked then
			if now >= nextFlicker then
				flickerUntil = now + S.flicker.time
				nextFlicker = now + S.flicker.every * (1 + S.flicker.jitter * (2 * rng:NextNumber() - 1))
			end
			if now < flickerUntil then
				bright *= S.flicker.depth
			end
		end
		local r = now - refilledAt
		local flash = if r < S.flash then 1 - r / S.flash else 0

		if rock then
			angle += math.rad(S.spin) * dt
			local bob = math.sin(now * S.bob.speed * math.pi * 2) * S.bob.height * rock.size.Magnitude
			local at = CFrame.new(0, bob, 0) * CFrame.Angles(0, angle, 0) * CFrame.Angles(math.rad(S.tilt), 0, 0)
			for i, q in rock.parts do
				q.part.CFrame = at * q.rel
				local base = if i == 1 then glow else core
				q.part.Color = empty:Lerp(base, bright):Lerp(Color3.new(1, 1, 1), flash)
				q.part.Transparency = S.empty * (1 - bright)
			end
		end

		-- the stage lamps
		local stage = 0
		if cost then
			for i, c in costs do
				if c == cost then
					stage = i
				end
			end
		end
		for i, lamp in lamps do
			local color = rgb(UI.lampOff)
			if i <= stage then
				local pulse = if i == stage
					then 1 - S.pulseDepth * (1 + math.sin(now * S.stagePulse * math.pi * 2)) / 2
					else 1
				color = rgb(UI.lampOff):Lerp(core, pulse)
			elseif not locked and value >= costs[i] then
				color = rgb(UI.lampOff):Lerp(glow, S.lampIdle)
			end
			lamp.BackgroundColor3 = color
		end
	end)
end

return StaffHud
