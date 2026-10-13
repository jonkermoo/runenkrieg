--!strict
-- Shooting effects on any soldier's weapon, local to this client (Config/Firing.Effects / Sounds): the muzzle flash,
-- the shot sound at the muzzle, a tracer to the hit, a bullet hole, a flash on a range target, the gun's kick at the
-- body's Hold motor, and the action worked by hand: the bolt turns up, slides back (the spent case flies out of
-- the ejection port), returns and turns down; on a reload the clip comes in from above (an en-bloc clip drops out
-- the bottom when its last round is fed). The parts move by their Motor6Ds' C0 (src/server/Armory rigs them), on
-- the body's weapon and, for the local player, on the first-person viewmodel's copy too (src/client/Viewmodel).
-- Rounds and clips show by the magazine count. src/client/Firing drives the local player; everyone else's shots and
-- actions arrive from the server.

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Firing)
local W = require(Shared.Config.Weapons)
local Audio = require(script.Parent.Audio)

local GunFx = {}

local E = Cfg.Effects

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local folder: Folder? = nil
local function fx(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "GunFx"
		f.Parent = workspace
		folder = f
	end
	return folder :: Folder
end

local function bit(size: Vector3, cf: CFrame, color: Color3, neon: boolean): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Parent = fx()
	return p
end

-- The Gun parts showing a character's weapon: the body's, and for the local player the viewmodel's copy.
function GunFx.guns(character: Model): { BasePart }
	local out = {}
	local tool = character:FindFirstChildOfClass("Tool")
	local gun = tool and tool:FindFirstChild("Gun")
	if gun and gun:IsA("BasePart") then
		table.insert(out, gun)
	end
	if character == Players.LocalPlayer.Character then
		local vm = workspace.CurrentCamera:FindFirstChild("Viewmodel")
		local vgun = vm and vm:FindFirstChild("Gun")
		if vgun and vgun:IsA("BasePart") then
			table.insert(out, vgun)
		end
	end
	return out
end

-- The gun the player sees: the viewmodel's while it is shown, else the body's.
function GunFx.visible(character: Model): BasePart?
	local guns = GunFx.guns(character)
	if #guns == 2 and character:GetAttribute("ViewmodelShown") == true then
		return guns[2]
	end
	return guns[1]
end

-- ---- sounds: made once per gun and reused (a Sound created when needed starts ~0.33 s late, KNOWN_TRAPS) ----
function GunFx.preload()
	local list = {}
	for _, s in Cfg.Sounds do
		local a = Instance.new("Sound")
		a.SoundId = "rbxassetid://" .. s.id
		table.insert(list, a)
	end
	task.spawn(function()
		ContentProvider:PreloadAsync(list)
	end)
end

function GunFx.sound(gun: BasePart, name: string)
	local owner = gun:FindFirstAncestorWhichIsA("Model")
	if owner and owner:GetAttribute("Muted") == true then
		return -- a muted soldier (the animation showcase's dummies, src/server/Showcase)
	end
	local s = gun:FindFirstChild("Fx_" .. name) :: Sound?
	if not s then
		local c = (Cfg.Sounds :: any)[name]
		local made = Instance.new("Sound")
		made.Name = "Fx_" .. name
		made.SoundId = "rbxassetid://" .. c.id
		made.Volume = c.volume
		Audio.spatial(made, if name == "Shot" then "Gunshot" else "Mechanism") -- realistic falloff (Config/Audio)
		if c.start or c.stop then -- only part of the file (KNOWN_TRAPS: store sounds carry extra noises)
			made.PlaybackRegionsEnabled = true
			made.PlaybackRegion = NumberRange.new(c.start or 0, c.stop or 600)
		end
		made.Parent = gun
		s = made
	end
	local snd = s :: Sound
	local c = (Cfg.Sounds :: any)[name]
	snd.Volume = c.volume
	snd.TimePosition = c.start or 0
	snd:Play()
	if c.stop and c.fade then -- fade out before the cut
		task.delay(math.max(0, c.stop - c.fade), function()
			TweenService:Create(snd, TweenInfo.new(c.fade, Enum.EasingStyle.Linear), { Volume = 0 }):Play()
		end)
	end
end

-- ---- the shot ----
function GunFx.flash(gun: BasePart)
	local muzzle = gun:FindFirstChild("Muzzle") :: Attachment?
	if not muzzle then
		return
	end
	local f = E.Flash
	local p = bit(Vector3.one * f.size, muzzle.WorldCFrame, rgb(f.color), true)
	p.Shape = Enum.PartType.Ball
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range = rgb(f.color), f.brightness, f.range
	light.Parent = p
	Debris:AddItem(p, f.time)
end

function GunFx.tracer(from: Vector3, to: Vector3)
	local t = E.Tracer
	local len = (to - from).Magnitude
	if len < 1 then
		return
	end
	local p = bit(Vector3.new(t.width, t.width, len), CFrame.lookAt((from + to) / 2, to), rgb(t.color), true)
	Debris:AddItem(p, t.time)
end

local holes: { Part } = {}
function GunFx.hole(at: Vector3, normal: Vector3?, part: Instance?)
	if not normal or not part or not part:IsA("BasePart") or not part.Anchored then
		return -- only on things that stay put
	end
	local h = E.Hole
	-- a thin disc lying on the surface (a cylinder's axis is its X)
	local p = bit(
		Vector3.new(0.02, h.size, h.size),
		CFrame.lookAt(at, at + normal) * CFrame.Angles(0, math.rad(90), 0),
		rgb(h.color),
		false
	)
	p.Shape = Enum.PartType.Cylinder
	table.insert(holes, p)
	if #holes > h.max then
		table.remove(holes, 1):Destroy()
	end
	Debris:AddItem(p, h.life)
end

-- a range target's block lights up when hit (src/dev/Range: models named Target_<distance>)
function GunFx.isTarget(part: Instance?): boolean
	local m = part and part.Parent
	return m ~= nil and m:IsA("Model") and string.sub(m.Name, 1, 7) == "Target_"
end

function GunFx.targetFlash(part: Instance?)
	if not part or not part:IsA("BasePart") or not GunFx.isTarget(part) then
		return
	end
	local was = part.Color
	part.Color = rgb(E.TargetFlash.color)
	task.delay(E.TargetFlash.time, function()
		part.Color = was
	end)
end

-- the gun kicks at the Hold motor (gun space: back along the barrel, muzzle up about the origin), easing back
function GunFx.kick(character: Model)
	local tool = character:FindFirstChildOfClass("Tool")
	local hold = tool and tool:FindFirstChild("Hold", true) :: Motor6D?
	if not hold then
		return
	end
	local b = Cfg.Recoil.body
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local u = math.clamp((os.clock() - t0) / b.time, 0, 1)
		local k = (1 - u) ^ 2
		if hold.Parent == nil or u >= 1 then
			hold.C1 = CFrame.identity
			conn:Disconnect()
			return
		end
		hold.C1 = (CFrame.new(0, 0, b.back * k) * CFrame.Angles(math.rad(b.pitch * k), 0, 0)):Inverse()
	end)
end

-- Everything a shot shows: the shooter's flash and sound, the tracer from the visible muzzle, the hole, the target.
function GunFx.shot(character: Model, hit: Vector3, normal: Vector3?, part: Instance?)
	local gun = GunFx.visible(character)
	if gun then
		GunFx.flash(gun)
		GunFx.sound(gun, "Shot")
		local muzzle = gun:FindFirstChild("Muzzle") :: Attachment?
		if muzzle then
			GunFx.tracer(muzzle.WorldPosition, hit)
		end
	end
	GunFx.kick(character)
	GunFx.hole(hit, normal, part)
	GunFx.targetFlash(part)
end

-- ---- the action ----
-- each moving part's rest C0, kept on the motor itself so a copy made mid-cycle (the viewmodel) knows it too
local function move(gun: BasePart, name: string, offset: CFrame)
	local m = gun:FindFirstChild(name) :: Motor6D?
	if not m or not m:IsA("Motor6D") then
		return
	end
	local rest = m:GetAttribute("RestC0")
	if typeof(rest) ~= "CFrame" then
		rest = m.C0
		m:SetAttribute("RestC0", rest)
	end
	m.C0 = (rest :: CFrame) * offset
end

local function show(gun: BasePart, name: string, visible: boolean)
	local p = gun.Parent and gun.Parent:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		p.Transparency = if visible then 0 else 1
	end
end

-- Rounds and clips as the magazine stands: an en-bloc clip sits in the magazine with its rounds while it has any; a
-- stripper clip only shows while loading.
function GunFx.loadout(character: Model, weapon: string, magazine: number)
	local en = W[weapon].ammo.clip == "Enbloc"
	for _, gun in GunFx.guns(character) do
		show(gun, "Rounds", magazine > 0)
		show(gun, "Bullets", magazine > 0)
		show(gun, "Clip", en and magazine > 0)
	end
end

local function eject(gun: BasePart)
	local port = gun:FindFirstChild("Eject") :: Attachment?
	local template = gun.Parent and gun.Parent:FindFirstChild("Casing")
	if not port or not template or not template:IsA("BasePart") then
		return
	end
	local c = E.Casing
	local p = template:Clone()
	p:ClearAllChildren()
	p.Transparency, p.LocalTransparencyModifier = 0, 0
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, true, false, false, false
	p.CollisionGroup = "Debris"
	p.CFrame = CFrame.new(port.WorldPosition) * template.CFrame.Rotation
	p.Parent = fx()
	local frame = gun.CFrame
	p.AssemblyLinearVelocity = frame:VectorToWorldSpace(Vector3.new(c.out, c.up, c.back))
		+ (gun.AssemblyLinearVelocity or Vector3.zero)
	p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * c.spin
	-- real gravity for the flight: a force holding up the rest of Roblox's
	local at = Instance.new("Attachment")
	at.Parent = p
	local lift = Instance.new("VectorForce")
	lift.Attachment0 = at
	lift.RelativeTo = Enum.ActuatorRelativeTo.World
	lift.ApplyAtCenterOfMass = true
	lift.Force = Vector3.new(0, p.AssemblyMass * (workspace.Gravity - c.gravity), 0)
	lift.Parent = p
	Debris:AddItem(lift, c.flight)
	Debris:AddItem(p, c.life)
end

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- actions under way and actions cut short (the rifle put away), per Tool
local running: { [Tool]: RBXScriptConnection } = setmetatable({}, { __mode = "k" }) :: any
type Cut = { weapon: string, action: string, out: string?, magazine: number, from: number, to: number }
local cut: { [Tool]: Cut } = setmetatable({}, { __mode = "k" }) :: any

-- The action cut short when this Tool was put away, if any (taken: it plays out once).
function GunFx.takeCut(tool: Tool): Cut?
	local c = cut[tool]
	cut[tool] = nil
	return c
end

-- The bolt (and clip) through a "Bolt" or "Reload" cycle (Config/Firing BoltCycle / ReloadCycle), playing the span
-- `from`..`to` of its timeline (0..1: the whole action; a bolt held open on an empty rifle stops at `back`, a reload
-- from an open bolt starts there, a resumed action plays its rest). `out`: what the opening bolt throws out
-- ("Casing"); `magazine`: rounds left in the magazine after it. Put away midway, it stops where it is and is kept
-- (GunFx.takeCut) to play out when the rifle is drawn again.
function GunFx.cycle(
	character: Model,
	weapon: string,
	action: string,
	out: string?,
	magazine: number,
	from: number?,
	to: number?
)
	local w = W[weapon]
	local a = w.action
	local s = w.scale
	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		return
	end
	local u0, u1 = from or 0, to or 1
	local time = (if action == "Bolt" then a.boltTime else a.reloadTime) * (u1 - u0)
	if time <= 0 then
		return
	end
	local turn, travel = math.rad(a.turn), a.travel * s[3]
	local cycle = if action == "Bolt" then Cfg.BoltCycle else Cfg.ReloadCycle :: any
	local en = w.ammo.clip == "Enbloc"
	local rise = Cfg.ClipRise * s[2]
	local t0 = os.clock()
	-- what already happened before `from` doesn't happen again
	local opened, ejected = u0 > cycle.up * 0.5, u0 > cycle.back
	local clipped, seated, closed = u0 > cycle.back, u0 > (cycle.clip or 2), u0 > cycle.forward
	-- the bolt goes forward after the shot's case is out (Bolt) or after the clip is in (Reload)
	local fwdFrom = if action == "Bolt" then cycle.back else cycle.clip
	local function pose(u: number)
		-- the bolt: up (turn), back (slide), forward, down
		local up = smooth(u / cycle.up)
		local back = smooth((u - cycle.up) / (cycle.back - cycle.up))
		local forward = smooth((u - fwdFrom) / (cycle.forward - fwdFrom))
		local down = smooth((u - cycle.forward) / (cycle.down - cycle.forward))
		local angle = turn * (up - down)
		local slide = travel * (back - forward)
		-- the clip on a reload: comes down from above between the bolt opening and closing
		local clipY: number? = nil
		if action == "Reload" then
			local c = smooth((u - cycle.back) / (cycle.clip - cycle.back))
			if u >= cycle.back and u < (if en then 2 else cycle.clip) then
				clipY = rise * (1 - c)
			end
		elseif en and magazine == 0 then
			-- the last round fed: the empty en-bloc clip drops out the bottom as the bolt closes
			local c = smooth((u - cycle.forward) / (cycle.down - cycle.forward))
			if u >= cycle.forward then
				clipY = -rise * c
			end
		end
		for _, gun in GunFx.guns(character) do
			move(gun, "Bolt", CFrame.new(0, 0, slide) * CFrame.Angles(0, 0, angle))
			if clipY then
				move(gun, "Clip", CFrame.new(0, clipY, 0))
				if en then
					move(gun, "Rounds", CFrame.new(0, clipY, 0))
				end
			end
		end
	end
	if running[tool] then
		running[tool]:Disconnect()
	end
	cut[tool] = nil
	pose(u0)
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local u = math.min(u0 + (os.clock() - t0) / time * (u1 - u0), u1)
		local gun = GunFx.visible(character)
		if not character.Parent or not gun or tool.Parent ~= character then
			-- put away (or gone) midway: stop here, keep the rest for when it's drawn again
			conn:Disconnect()
			running[tool] = nil
			if u < u1 then
				cut[tool] = {
					weapon = weapon,
					action = action,
					out = if ejected then nil else out,
					magazine = magazine,
					from = u,
					to = u1,
				}
			end
			return
		end
		pose(u)
		if not opened and u >= cycle.up * 0.5 then
			opened = true
			GunFx.sound(gun, "BoltOpen")
		end
		if not ejected and u >= cycle.back then
			ejected = true
			if out == "Casing" then
				eject(gun)
			end
		end
		if action == "Reload" and not clipped and u >= cycle.back then
			clipped = true
			for _, g in GunFx.guns(character) do
				show(g, "Clip", true)
				if en then
					show(g, "Rounds", true)
					show(g, "Bullets", true)
				end
			end
		end
		if action == "Reload" and clipped and not seated and u >= cycle.clip then
			seated = true
			GunFx.sound(gun, "ClipIn")
			GunFx.loadout(character, weapon, magazine) -- the rounds are in; a stripper clip comes away
		end
		if not closed and u >= cycle.forward then
			closed = true
			GunFx.sound(gun, "BoltClose")
		end
		if u >= u1 then
			conn:Disconnect()
			running[tool] = nil
			if u1 >= 1 then -- closed: every part back at rest (a bolt held open stays back)
				for _, g in GunFx.guns(character) do
					move(g, "Bolt", CFrame.identity)
					move(g, "Clip", CFrame.identity)
					move(g, "Rounds", CFrame.identity)
				end
			end
			GunFx.loadout(character, weapon, magazine)
		end
	end)
	running[tool] = conn
end

return GunFx
