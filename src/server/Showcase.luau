--!strict
-- The animation showcase (Config/Showcase): dummies off the map, one per animation, looping it as other players see
-- it (third person). Built at server start in the DEV place only, from Config/Locomotion and Config/Weapons, so it
-- is always current. The dummies' tracks play on the server and replicate; their weapon actions go out like a
-- player's ("Shot" / "WeaponAction"), so src/client/GunFx moves the bolt and clip, ejects the case and flashes for
-- everyone. Nothing here is hit or hurt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Showcase)
local Loco = require(Shared.Config.Locomotion)
local U = require(Shared.Config.Uniforms)
local W = require(Shared.Config.Weapons)
local Spells = require(Shared.Config.Spells)
local SpellRules = require(Shared.Rules.Spells)
local Net = require(Shared.Net)
local Armory = require(script.Parent.Armory)
local Bodies = require(script.Parent.Bodies)

local Showcase = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local folder: Folder

local function label(parent: BasePart, text: string, offset: number, size: number, range: number)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, size + 8)
	gui.StudsOffset = Vector3.new(0, offset, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = range -- near rows only, so the rows behind don't pile their labels on top
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextSize = size
	t.TextColor3 = rgb(Cfg.Colors.Label)
	t.TextStrokeTransparency = 0.4
	t.Text = text
	t.Parent = gui
	gui.Parent = parent
end

-- a soldier in the uniform, standing anchored at `cf`
local function dummy(name: string, cf: CFrame, parent: Instance?): Model
	local kit = U.Kits[U.Default]
	local skin = rgb(kit.skin)
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor, desc.TorsoColor = skin, skin
	desc.LeftArmColor, desc.RightArmColor, desc.LeftLegColor, desc.RightLegColor = skin, skin, skin, skin
	local m = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6)
	m.Name = name
	for _, d in m:GetDescendants() do
		if d:IsA("BaseScript") then
			d:Destroy() -- no stock Animate: the showcase plays the tracks
		end
	end
	local humanoid = m:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	m:SetAttribute("Muted", true) -- their guns make no sound (user 2026-10-12: too loud; src/client/GunFx)
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart
	root.Anchored = true
	m.PrimaryPart = root -- the model's own pivot is its box centre: place it by the root
	m:PivotTo(cf)
	m.Parent = parent or folder
	Bodies.apply(m)
	return m
end

local function animator(m: Model): Animator
	local humanoid = m:FindFirstChildOfClass("Humanoid") :: Humanoid
	local a = humanoid:FindFirstChildOfClass("Animator")
	if not a then
		a = Instance.new("Animator")
		a.Parent = humanoid
	end
	return a :: Animator
end

local function track(m: Model, id: number, priority: Enum.AnimationPriority, looped: boolean): AnimationTrack
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. id
	local t = animator(m):LoadAnimation(anim)
	t.Priority = priority
	t.Looped = looped
	return t
end

-- a movement cycle at its game pace (Config/Locomotion keyed / cycle)
local function base(m: Model, name: string): AnimationTrack
	local a = (Loco.Animations :: any)[name]
	local t = track(m, a.id, Enum.AnimationPriority.Core, true)
	t:Play(0)
	if a.keyed and a.cycle then
		t:AdjustSpeed(a.keyed / a.cycle)
	end
	return t
end

local function arm(m: Model, weapon: string): Tool
	local tool = Armory.tool(weapon)
	local hold = tool:FindFirstChild("Hold", true) :: Motor6D
	hold.Part0 = m:FindFirstChild("Torso") :: BasePart
	local w = W[weapon]
	if w.ammo then
		tool:SetAttribute("Magazine", w.ammo.capacity)
		tool:SetAttribute("Chambered", true)
		tool:SetAttribute("Spent", false)
	end
	tool.Parent = m
	return tool
end

-- a muted, anchored soldier and a weapon in its hands (src/server/TestShooter uses them too)
Showcase.dummy = dummy
Showcase.arm = arm

local function sorted(t: { [string]: any }, first: { string }?): { string }
	local out, seen = {}, {}
	for _, k in first or {} do
		if t[k] ~= nil then
			table.insert(out, k)
			seen[k] = true
		end
	end
	local rest = {}
	for k in t do
		if not seen[k] then
			table.insert(rest, k)
		end
	end
	table.sort(rest)
	for _, k in rest do
		table.insert(out, k)
	end
	return out
end

-- A shot from a showcase dummy: the flash, sound, kick and a short tracer along its barrel, for everyone.
local function shoot(m: Model, tool: Tool)
	local gun = tool:FindFirstChild("Gun") :: BasePart?
	local muzzle = gun and gun:FindFirstChild("Muzzle") :: Attachment?
	if muzzle then
		local origin = muzzle.WorldPosition
		Net.event("Shot"):FireAllClients(
			m,
			tool:GetAttribute("Weapon"),
			origin,
			origin + muzzle.WorldCFrame.LookVector * Cfg.Tracer,
			nil,
			nil
		)
	end
end

function Showcase.start()
	if game.PlaceId ~= Cfg.PlaceId then
		return
	end
	local old = workspace:FindFirstChild("DevShowcase")
	if old then
		old:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "DevShowcase"
	folder.Parent = workspace
	local O = Vector3.new(Cfg.Origin[1], Cfg.Origin[2], Cfg.Origin[3])

	-- the rows: movement first, then one per weapon
	local rows: { { title: string, items: { any } } } = {}
	local moves = {}
	for _, name in sorted(Loco.Animations :: any, Cfg.Movement) do
		if not Cfg.Skip[name] then
			table.insert(moves, { kind = "move", name = name })
		end
	end
	table.insert(rows, { title = "Movement", items = moves })
	for _, weapon in sorted(W :: any) do
		local w = W[weapon]
		local items = {}
		local listed = {}
		for _, h in Cfg.Holds do
			if (w.holds :: any)[h.hold] then
				table.insert(items, { kind = "hold", weapon = weapon, spec = h })
				listed[h.hold] = true
			end
		end
		for _, hold in sorted(w.holds :: any) do -- a hold added later shows over idle until Config/Showcase places it
			if not listed[hold] then
				table.insert(items, { kind = "hold", weapon = weapon, spec = { hold = hold, base = "idle" } })
			end
		end
		for _, a in Cfg.Actions do
			-- guns only; single rounds: only a rifle that loads them; a clip reload: not for loose shells (a pump gun)
			if w.ammo and (a.action ~= "Load" or w.single) and (a.action ~= "Reload" or w.ammo.clip ~= "Loose") then
				table.insert(items, { kind = "action", weapon = weapon, spec = a })
			end
		end
		if weapon == Cfg.CastWeapon then
			for _, c in Cfg.Casts do
				table.insert(items, { kind = "cast", weapon = weapon, spec = c })
			end
		end
		table.insert(rows, { title = w.display, items = items })
	end

	-- the floor under it all
	local wide = 0
	for _, r in rows do
		wide = math.max(wide, #r.items)
	end
	local floor = Instance.new("Part")
	floor.Name = "Floor"
	floor.Anchored = true
	floor.Material = Enum.Material.SmoothPlastic
	floor.Color = rgb(Cfg.Colors.Floor)
	floor.Size = Vector3.new(wide * Cfg.Spacing + 12, 1, #rows * Cfg.RowGap + 16)
	floor.CFrame = CFrame.new(O + Vector3.new((wide - 1) * Cfg.Spacing / 2, -0.5, -(#rows - 1) * Cfg.RowGap / 2))
	floor.Parent = folder

	local STAND = 3 -- the R6 root's height over the floor
	for r, row in rows do
		local z = O.Z - (r - 1) * Cfg.RowGap
		local sign = Instance.new("Part")
		sign.Name = "Row_" .. row.title
		sign.Anchored, sign.CanCollide, sign.Transparency = true, false, 1
		sign.Size = Vector3.one
		sign.CFrame = CFrame.new(O.X - Cfg.Spacing, O.Y + STAND, z)
		sign.Parent = folder
		label(sign, row.title, 2, 22, 90)
		for i, item in row.items do
			local air = item.kind == "cast" and item.spec.air == true -- a floating caster hovers off the floor
			local pos = Vector3.new(O.X + (i - 1) * Cfg.Spacing, O.Y + STAND + (if air then Cfg.AirLift else 0), z)
			-- facing the viewer (+z); action dummies side-on, right side to the viewer, firing along +x
			local side = item.kind == "action" or item.kind == "cast"
			local look = if side then pos + Vector3.new(1, 0, 0) else pos + Vector3.new(0, 0, 1)
			local m = dummy(`{row.title} {i}`, CFrame.lookAt(pos, look))
			local root = m:FindFirstChild("HumanoidRootPart") :: BasePart
			if item.kind == "move" then
				base(m, item.name)
				label(root, item.name, 4, 16, Cfg.LabelRange)
			elseif item.kind == "hold" then
				local h = item.spec
				local w = W[item.weapon]
				arm(m, item.weapon)
				local b = base(m, h.base)
				if h.once then
					local over = track(m, (w.holds :: any)[h.over], Enum.AnimationPriority.Action, true)
					over:Play(0)
					local once = track(m, (w.holds :: any)[h.hold], Enum.AnimationPriority.Action2, false)
					task.spawn(function()
						while m.Parent do
							once:Play(0)
							task.wait(Cfg.Replay)
						end
					end)
					label(root, `{h.hold} (over {h.over})`, 4, 16, Cfg.LabelRange)
				else
					local t = track(m, (w.holds :: any)[h.hold], Enum.AnimationPriority.Action, true)
					t:Play(0)
					t:AdjustSpeed(b.Speed) -- in step with the cycle it rides on
					label(root, if h.base == "idle" then h.hold else `{h.hold} + {h.base}`, 4, 16, Cfg.LabelRange)
				end
			elseif item.kind == "cast" then
				-- the staff's attack: published as attributes the clients draw the spell from (src/client/CastShow):
				-- CastHeld while a circle is held (counting up while charging), CastCharging while charging (the laser),
				-- CastStage + a new CastFire on the shot (CastHip: from the hip)
				local c = item.spec
				local w = W[item.weapon]
				local fire = w.fire :: any
				arm(m, item.weapon)
				base(m, if c.air then "float" else "idle")
				local ready = track(m, w.holds.ready, Enum.AnimationPriority.Action, true)
				local one = track(m, w.holds.aim :: number, Enum.AnimationPriority.Action, true)
				local two = track(m, w.holds.aimTwo :: number, Enum.AnimationPriority.Action, true)
				-- floating: the charge leaning back
				local chargeId = if c.air then w.holds.airCharge else w.holds.charge
				local charge = track(m, chargeId :: number, Enum.AnimationPriority.Action2, false)
				local kicks = {}
				for _, k in { "quick", "quickAim", "medium", "mediumTwo" } do
					kicks[k] = track(m, fire[k], Enum.AnimationPriority.Action3, false)
				end
				m:SetAttribute("CastShow", true)
				m:SetAttribute("CastHip", c.hip == true)
				label(
					root,
					if c.hip
						then "staff: quick fire (hip)"
						elseif c.air then `staff: floating, stage {c.stage}`
						else `staff: aimed, stage {c.stage}`,
					4,
					16,
					Cfg.LabelRange
				)
				task.spawn(function()
					task.wait(i * 0.4)
					local fired = 0
					local function cast(kick: string)
						fired += 1
						m:SetAttribute("CastHeld", nil)
						m:SetAttribute("CastCharging", nil)
						m:SetAttribute("CastStage", c.stage)
						m:SetAttribute("CastFire", fired)
						kicks[kick]:Play(0.05)
					end
					if c.hip then
						ready:Play(0)
						while m.Parent do
							task.wait(c.rest)
							cast("quick")
						end
						return
					end
					while m.Parent do
						one:Play(0.2)
						two:Stop(0.2)
						-- aiming: the first circle opens and is held
						m:SetAttribute("CastHeld", 0)
						task.wait(c.ready)
						-- the click, held: charging
						m:SetAttribute("CastCharging", true)
						charge:Play(0.1)
						charge:AdjustSpeed(0)
						local t0, held, both = os.clock(), 0, false
						while held < c.held and m.Parent do
							held = os.clock() - t0
							local ct = SpellRules.chargeTime(Spells.Stages, Spells.Staff.ChargeLoop, held)
							charge.TimePosition = math.min(ct, math.max(charge.Length - 0.01, 0))
							m:SetAttribute("CastHeld", held)
							if not both and held >= Spells.Staff.TwoHands then
								both = true
								two:Play(0.2)
								one:Stop(0.2)
							end
							RunService.Heartbeat:Wait()
						end
						charge:Stop(0.1)
						cast(if c.stage == 1 then "quickAim" elseif both then "mediumTwo" else "medium")
						task.wait(c.rest)
					end
				end)
			else
				local a = item.spec
				local w = W[item.weapon]
				local tool = arm(m, item.weapon)
				base(m, "idle")
				track(m, (w.holds :: any)[a.over], Enum.AnimationPriority.Action, true):Play(0)
				local name = if a.action == "Bolt"
					then "fire + bolt"
					elseif a.action == "Load" then "single rounds"
					else "reload"
				label(root, name, 4, 16, Cfg.LabelRange)
				task.spawn(function()
					task.wait(i * 0.3) -- not all in unison
					while m.Parent do
						if a.action == "Bolt" then
							shoot(m, tool)
							task.wait(a.shotFirst)
							Net.event("WeaponAction"):FireAllClients(m, "Bolt", "Casing", 0, 1, nil)
							task.wait(a.every - a.shotFirst)
						elseif a.action == "Load" then
							Net.event("WeaponAction"):FireAllClients(m, "Load", nil, 0, a.rounds, nil)
							task.wait(a.every)
						else
							Net.event("WeaponAction"):FireAllClients(m, "Reload", nil, 0, 1, nil)
							task.wait(a.every)
						end
					end
				end)
			end
		end
	end
end

return Showcase
