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
local Impacts = require(script.Parent.Impacts)

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
		if not (s :: any).id then
			continue -- variants heard by everyone else (src/client/ShotAudio preloads them)
		end
		local a = Instance.new("Sound")
		a.SoundId = "rbxassetid://" .. s.id
		table.insert(list, a)
	end
	task.spawn(function()
		ContentProvider:PreloadAsync(list)
	end)
end

-- The weapon's own sound (Config/Weapons `sounds`, the Gun part's "Weapon" attribute) or Config/Firing's.
local function soundOf(gun: BasePart, name: string): any
	local weapon = gun:GetAttribute("Weapon")
	local w = type(weapon) == "string" and W[weapon] or nil
	return (w and w.sounds and w.sounds[name]) or (Cfg.Sounds :: any)[name]
end

function GunFx.sound(gun: BasePart, name: string)
	local owner = gun:FindFirstAncestorWhichIsA("Model")
	if owner and owner:GetAttribute("Muted") == true then
		return -- a muted soldier (the animation showcase's dummies, src/server/Showcase)
	end
	local s = gun:FindFirstChild("Fx_" .. name) :: Sound?
	if not s then
		local c = soundOf(gun, name)
		local made = Instance.new("Sound")
		made.Name = "Fx_" .. name
		made.SoundId = "rbxassetid://" .. c.id
		made.Volume = c.volume
		-- realistic falloff (Config/Audio); this player's own gun's action from wherever the camera is
		local me = Players.LocalPlayer.Character -- (an ancestor check: a Tool is a Model too, so `owner` is the Tool)
		local own = me ~= nil and gun:IsDescendantOf(me)
		Audio.spatial(made, if name == "Shot" then "Gunshot" elseif own then "OwnMechanism" else "Mechanism")
		if c.start or c.stop then -- only part of the file (KNOWN_TRAPS: store sounds carry extra noises)
			made.PlaybackRegionsEnabled = true
			made.PlaybackRegion = NumberRange.new(c.start or 0, c.stop or 600)
		end
		made.Parent = gun
		s = made
	end
	local snd = s :: Sound
	local c = soundOf(gun, name)
	if name == "Shot" then
		-- each shot its own copy (user 2026-10-13: a quick second shot cut the first one off), gone once it has played
		snd = snd:Clone()
		snd.Parent = gun
		snd.Ended:Once(function()
			snd:Destroy()
		end)
		Debris:AddItem(snd, 10)
	end
	snd.Volume = c.volume
	snd.TimePosition = c.start or 0
	snd:Play()
	if c.stop and c.fade then -- fade out before the cut (stop is a time in the file: the play began at `start`)
		task.delay(math.max(0, c.stop - (c.start or 0) - c.fade), function()
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

-- Everything a shot shows: the shooter's flash and sound, the tracer from the visible muzzle, the hole, what the
-- surface throws up and leaves from canopies on the way (src/client/Impacts), the target.
-- `more`: a shotgun's other pellets ({ hit, normal, part } each): a tracer, a hole and a target flash apiece.
-- `heard`: someone else's shot, whose sound src/client/ShotAudio plays instead.
function GunFx.shot(character: Model, hit: Vector3, normal: Vector3?, part: Instance?, more: { any }?, heard: boolean?)
	local gun = GunFx.visible(character)
	local muzzle = gun and gun:FindFirstChild("Muzzle") :: Attachment?
	if gun then
		GunFx.flash(gun)
		if not heard then
			-- on the body's gun, as the mechanism's sounds (GunFx.cycle): the viewmodel's goes out of the DataModel when
			-- aiming ends, which cut the shot playing on it short (user 2026-10-22)
			GunFx.sound(GunFx.guns(character)[1] or gun, "Shot")
		end
	end
	GunFx.kick(character)
	for _, h in { { hit, normal, part }, table.unpack(more or {}) } do
		if typeof(h[1]) == "Vector3" then
			if muzzle then
				GunFx.tracer(muzzle.WorldPosition, h[1])
			end
			GunFx.hole(h[1], h[2], h[3])
			Impacts.shot(if muzzle then muzzle.WorldPosition else nil, h[1], h[2], h[3])
			GunFx.targetFlash(h[3])
		end
	end
	GunFx.animateHammer(character)
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

-- The viewmodel's gun brought back in line with the body's (src/client/Viewmodel, as it comes into view): out of first
-- person it is out of the DataModel, so an action that played on meanwhile moved only the body's gun and left the copy
-- where it was (user 2026-10-20: the bolt handle up on a loaded rifle on aiming again).
function GunFx.match(character: Model, copy: BasePart)
	local tool = character:FindFirstChildOfClass("Tool")
	local gun = tool and tool:FindFirstChild("Gun")
	if not gun or not gun:IsA("BasePart") then
		return
	end
	-- (only the moving parts the actions pose, which carry their rest: not the "Hold" the look tilt swings)
	for _, m in gun:GetChildren() do
		local twin = copy:FindFirstChild(m.Name)
		local rest = m:GetAttribute("RestC0")
		if m:IsA("Motor6D") and typeof(rest) == "CFrame" and twin and twin:IsA("Motor6D") then
			twin:SetAttribute("RestC0", rest)
			twin.C0 = m.C0
		end
	end
	local holder, own = copy.Parent, gun.Parent
	if not holder or not own then
		return
	end
	local w = W[tostring(gun:GetAttribute("Weapon"))]
	local names = { "Rounds", "Bullets", "Clip", "Magazine", table.unpack(w and w.feed and w.feed.parts or {}) }
	for _, name in w and w.revolver and w.revolver.rounds or {} do -- (a revolver's rounds, chamber by chamber)
		table.insert(names, name)
	end
	for _, name in w and w.revolver and w.revolver.bullets or {} do -- (and their bullets)
		table.insert(names, name)
	end
	for _, name in names do
		local from, to = own:FindFirstChild(name), holder:FindFirstChild(name)
		if from and to and from:IsA("BasePart") and to:IsA("BasePart") then
			to.Transparency = from.Transparency
		end
	end
end

-- Rounds and clips as the magazine stands: an en-bloc clip sits in the magazine with its rounds while it has any; a
-- stripper clip only shows while loading.
-- A pump gun's shell on the carrier shows while the tube has shells.
function GunFx.loadout(character: Model, weapon: string, magazine: number)
	local w = W[weapon]
	local en = w.ammo.clip == "Enbloc"
	for _, gun in GunFx.guns(character) do
		show(gun, "Rounds", magazine > 0)
		show(gun, "Bullets", magazine > 0)
		show(gun, "Clip", en and magazine > 0)
		for _, name in if w.feed then w.feed.parts else {} do
			show(gun, name, magazine > 0)
		end
	end
end

-- A shot lets the hammer fall (a pump gun's rests cocked: it falls `hammer.cock` degrees forward about its pin; the
-- pump's back stroke pushes it down again, GunFx.cycle). `cocked`: 1 at rest, 0 fallen.
local function hammerAt(w: any, cocked: number): CFrame
	return CFrame.Angles(-math.rad(w.hammer.cock) * (1 - cocked), 0, 0)
end

-- A share of the way along a curve of evenly spaced values (Config/Weapons hammer.push).
local function along(curve: { number }, share: number): number
	local x = math.clamp(share, 0, 1) * (#curve - 1)
	local i = math.floor(x)
	if i >= #curve - 1 then
		return curve[#curve]
	end
	return curve[i + 1] + (curve[i + 2] - curve[i + 1]) * (x - i)
end

function GunFx.animateHammer(character: Model)
	local tool = character:FindFirstChildOfClass("Tool")
	local w = tool and W[tool:GetAttribute("Weapon") :: string]
	if not w or not w.hammer then
		return
	end
	for _, gun in GunFx.guns(character) do
		move(gun, "Hammer", hammerAt(w, 0))
	end
end

-- Throws a loose copy of a part off the gun (a spent case out of the port, a stripper clip off the guides): real
-- gravity for its flight (a force holding up the rest of Roblox's), gone after a while.
local function fling(copy: BasePart, gun: BasePart, at: CFrame, push: Vector3)
	local c = E.Casing
	copy:ClearAllChildren()
	copy.Transparency, copy.LocalTransparencyModifier = 0, 0
	copy.Anchored, copy.CanCollide, copy.CanQuery, copy.CanTouch, copy.Massless = false, true, false, false, false
	copy.CollisionGroup = "Debris"
	copy.CFrame = at
	copy.Parent = fx()
	copy.AssemblyLinearVelocity = gun.CFrame:VectorToWorldSpace(push) + (gun.AssemblyLinearVelocity or Vector3.zero)
	copy.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * c.spin
	local a = Instance.new("Attachment")
	a.Parent = copy
	local lift = Instance.new("VectorForce")
	lift.Attachment0 = a
	lift.RelativeTo = Enum.ActuatorRelativeTo.World
	lift.ApplyAtCenterOfMass = true
	lift.Force = Vector3.new(0, copy.AssemblyMass * (workspace.Gravity - c.gravity), 0)
	lift.Parent = copy
	Debris:AddItem(lift, c.flight)
	Debris:AddItem(copy, c.life)
end

-- the weapon's spent case (Config/Weapons `eject`, else "Casing"): several parts go as one piece (a shell's hull
-- and its brass head), the rest welded to the first
local function eject(gun: BasePart, weapon: string?)
	local port = gun:FindFirstChild("Eject") :: Attachment?
	local holder = gun.Parent
	local names = (weapon and W[weapon] and W[weapon].eject) or { "Casing" }
	local template = holder and holder:FindFirstChild(names[1])
	if not port or not holder or not template or not template:IsA("BasePart") then
		return
	end
	local c = E.Casing
	local copy = template:Clone()
	fling(copy, gun, CFrame.new(port.WorldPosition) * template.CFrame.Rotation, Vector3.new(c.out, c.up, c.back))
	for i = 2, #names do
		local t = holder:FindFirstChild(names[i])
		if t and t:IsA("BasePart") then
			local more = t:Clone()
			more:ClearAllChildren()
			more.Transparency, more.LocalTransparencyModifier = 0, 0
			more.Anchored, more.CanCollide, more.CanQuery, more.CanTouch, more.Massless =
				false, false, false, false, true
			more.CFrame = copy.CFrame * template.CFrame:ToObjectSpace(t.CFrame)
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = copy, more
			weld.Parent = more
			more.Parent = copy
		end
	end
end

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- ---- the clip in the hand (a reload; user 2026-10-13: the ammo is there, and a reload cut short while holding the
-- clip still holds it when it carries on) ----
-- Made from the gun's own clip and rounds, copied: an en-bloc clip with its rounds as they sit in the magazine; a
-- stripper clip with the magazine's rounds moved up into it (heads against the clip). Its place comes from the
-- reload's timeline alone (Config/Firing.ReloadCycle), so a reload resumed anywhere shows it where it was: in the
-- right hand from `grab` (the fist on its top, as the animation brings the hand to the clip's seat), set in by `set`,
-- pushed down by `clip` (an en-bloc clip into the magazine, where the gun's own clip takes over; a stripper clip's
-- rounds out of it), the empty stripper clip flying off as the bolt goes forward.
type PropPart = { part: BasePart, rel: CFrame, round: boolean }
type Prop = { parts: { PropPart }, gun: BasePart, hand: BasePart?, side: number, flung: boolean }

-- the hand point in an R6 arm (tools/animation/build.luau FIST); the hand pinches the clip from its right side, the
-- clip's top this far to the gun's left of it (tools/animation/reload.luau SIDE): beside the hand's 1-stud block, not
-- inside it
local FIST = Vector3.new(0, -0.8, 0)
local SIDE = 0.55
local FIRST_SIDE = 0.85 -- first person (the viewmodel's clip): the hand's block near the camera needs more room

local function makeProp(gun: BasePart, weapon: string): Prop?
	local w = W[weapon]
	local r, s = w.reload, w.scale
	local holder = gun.Parent
	if not holder then
		return nil
	end
	local rig = if holder:IsA("Tool") then holder.Parent else holder
	local hand = rig and rig:FindFirstChild("Right Arm") :: BasePart?
	local clip = holder:FindFirstChild("Clip") :: BasePart?
	local rounds = holder:FindFirstChild("Rounds") :: BasePart?
	if not clip then
		return nil
	end
	move(gun, "Clip", CFrame.identity)
	move(gun, "Rounds", CFrame.identity)
	local top = CFrame.new(r.clipTop[1] * s[1], r.clipTop[2] * s[2], r.clipTop[3] * s[3])
	local shift = CFrame.identity
	if r.entry <= 0 and rounds then
		local c = gun.CFrame:ToObjectSpace(clip.CFrame)
		local q = gun.CFrame:ToObjectSpace(rounds.CFrame)
		shift = CFrame.new(0, c.Y - q.Y, (c.Z - clip.Size.Z / 2) - (q.Z + rounds.Size.Z / 2))
	end
	local parts = {}
	local function add(p: Instance?, round: boolean)
		if not p or not p:IsA("BasePart") then
			return
		end
		local copy = p:Clone()
		copy:ClearAllChildren()
		copy.Name = "Held" .. p.Name
		copy.Anchored, copy.CanCollide, copy.CanQuery, copy.CanTouch, copy.CastShadow = true, false, false, false, false
		copy.Transparency, copy.LocalTransparencyModifier = 0, 0
		local rel = top:Inverse() * (if round then shift else CFrame.identity) * gun.CFrame:ToObjectSpace(p.CFrame)
		copy.Parent = holder
		table.insert(parts, { part = copy, rel = rel, round = round })
	end
	add(clip, false)
	add(rounds, true)
	add(holder:FindFirstChild("Bullets"), true)
	local side = if holder:IsA("Tool") then SIDE else FIRST_SIDE
	return { parts = parts, gun = gun, hand = hand, side = side, flung = false }
end

local function dropProp(prop: Prop)
	for _, p in prop.parts do
		p.part:Destroy()
	end
	table.clear(prop.parts)
end

-- the clip at timeline share u of a reload (C: its grab / set / clip shares; the second charger's, Reload2)
local function poseProp(prop: Prop, weapon: string, u: number, C: { grab: number, set: number, clip: number })
	local w = W[weapon]
	local r, s = w.reload, w.scale
	local gun = prop.gun
	local seat = gun.CFrame * CFrame.new(r.clipTop[1] * s[1], r.clipTop[2] * s[2], r.clipTop[3] * s[3])
	local entry = seat * CFrame.new(0, r.entry * s[2], 0)
	local en = r.entry > 0
	local topCF: CFrame
	local drop = 0 -- how far a stripper clip's rounds have gone down out of it
	if u < C.set then
		local held = entry
		if prop.hand then
			held = CFrame.new(prop.hand.CFrame:PointToWorldSpace(FIST) - gun.CFrame.RightVector * prop.side)
				* gun.CFrame.Rotation
		end
		-- the last stretch settles it exactly onto its place over the guides / the magazine
		topCF = held:Lerp(entry, smooth((u - (C.set - 0.05)) / 0.05))
	elseif u < C.clip then
		local k = smooth((u - C.set) / (C.clip - C.set))
		if en then
			topCF = entry:Lerp(seat, k)
		else
			topCF = seat
			drop = k
		end
	else
		topCF = seat
		drop = 1
	end
	local depth = (r.depth or 0.17) * s[2] -- a stripper clip's height: the rounds leave it
	for _, p in prop.parts do
		if p.round and not en then
			p.part.CFrame = topCF * CFrame.new(0, -depth * drop, 0) * p.rel
			p.part.Transparency = if drop >= 1 then 1 else 0
		else
			p.part.CFrame = topCF * p.rel
		end
	end
end

-- ---- the reload animations (tools/animation/reload.luau): the body's (our own, which replicates, or a soldier no
-- player owns: the animation showcase's dummies) and the first-person viewmodel's ----
-- Loaded once per animator and reused. Held strongly and dropped when the animator goes: a weak-keyed table lost its
-- entries whenever the Animator's Luau handle was collected (the instance lives on), so every action loaded new tracks
-- until the showcase dummies hit Roblox's 64-track limit and their reloads stopped playing (KNOWN_TRAPS).
local loaded: { [Animator]: { [number]: AnimationTrack } } = {}

local function track(animator: Animator, id: number): AnimationTrack
	local set = loaded[animator]
	if not set then
		set = {}
		loaded[animator] = set
		animator.Destroying:Connect(function()
			loaded[animator] = nil
		end)
	end
	local t = set[id]
	if not t then
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. id
		t = animator:LoadAnimation(anim)
		t.Priority = Enum.AnimationPriority.Action3
		t.Looped = false
		set[id] = t
	end
	return t
end

local function animatorOf(model: Instance?): Animator?
	local h = model and model:FindFirstChildOfClass("Humanoid")
	return h and h:FindFirstChildOfClass("Animator")
end

-- The viewmodel's Animator while the rig is in view (src/client/Viewmodel takes it out of the DataModel in third
-- person and stops its tracks): an action under way picks its first-person arms up where it is when the rig comes back.
local function viewmodelAnimator(): Animator?
	return animatorOf(workspace.CurrentCamera:FindFirstChild("Viewmodel"))
end

-- The first-person arms for an action (0: none): the reload's, or the hand working the bolt (aimed: the shouldered
-- variant; a pump gun's left hand, the pump).
local function firstAction(character: Model, weapon: string, action: string): number
	local w = W[weapon]
	if action == "Reload2" then
		return w.reload.firstPersonTwo or 0
	elseif action == "Reload" then
		return w.reload.firstPerson
	elseif action == "Auto" or not w.bolt then
		return 0
	end
	local hold = character:GetAttribute("Hold")
	local aimed = hold == "aim" or hold == "crouchAim"
	return (if aimed then w.bolt.firstAim else w.bolt.firstReady) or 0
end

-- The arms for an action, from timeline share u0: a reload, and working the bolt (aimed: the shouldered variant; any
-- other hold, or a soldier with no hold set such as the showcase's: by `Hold`, the showcase's bolt dummies aim), in
-- both views.
local function playAction(character: Model, weapon: string, action: string, u0: number): { AnimationTrack }
	local w = W[weapon]
	local two = action == "Reload2" -- (two chargers: their own animations, the reload plus one clipTime)
	local reload = action == "Reload" or two
	local time = if two
		then w.action.reloadTime + (w.action.clipTime or 0)
		elseif reload then w.action.reloadTime
		else w.action.boltTime
	local list = {}
	if action == "Auto" then
		return list -- a semi-automatic's action cycles itself: no hand on it
	end
	local function start(animator: Animator?, id: number)
		if not animator or id == 0 then
			return
		end
		local t = track(animator, id)
		t:Play(if u0 > 0 then Cfg.ResumeFade else 0.1)
		t.TimePosition = u0 * time
		table.insert(list, t)
	end
	local own = character == Players.LocalPlayer.Character
	if own or not Players:GetPlayerFromCharacter(character) then
		local body = if two then w.reload.bodyTwo or 0 else w.reload.body
		if not reload then
			local hold = character:GetAttribute("Hold")
			local aimed = hold == nil or hold == "aim" or hold == "crouchAim"
			body = if aimed then w.bolt.aim else w.bolt.ready
		end
		start(animatorOf(character), body)
	end
	if own then
		start(viewmodelAnimator(), firstAction(character, weapon, action))
	end
	return list
end

-- actions under way (how to stop each) and actions cut short (the rifle put away), per Tool
local running: { [Tool]: () -> () } = setmetatable({}, { __mode = "k" }) :: any
-- (a cut single load: from = seconds into it, to = rounds going in, magazine = the room it had)
type Cut = { weapon: string, action: string, out: string?, magazine: number, from: number, to: number }
local cut: { [Tool]: Cut } = setmetatable({}, { __mode = "k" }) :: any

-- The action cut short when this Tool was put away, if any (taken: it plays out once).
function GunFx.takeCut(tool: Tool): Cut?
	local c = cut[tool]
	cut[tool] = nil
	return c
end

-- The bolt (and the reload's hands and clip) through a "Bolt" or "Reload" cycle (Config/Firing BoltCycle /
-- ReloadCycle; a semi-automatic's self-cycling action after a shot: "Auto", AutoCycle), playing the span `from`..`to` of its timeline (0..1: the whole action; a bolt held open on an empty
-- rifle stops at `back`, a reload from an open bolt starts there, a resumed action plays its rest). `out`: what the
-- opening bolt throws out ("Casing"); `magazine`: rounds left in the magazine after it. Put away midway, it stops where
-- it is and is kept (GunFx.takeCut) to play out when the rifle is drawn again.
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
	local two = action == "Reload2" -- a semi-automatic pressing in two chargers (Config/Firing.ReloadCycleTwo)
	local reload = action == "Reload" or two
	local whole = if two then a.reloadTime + (a.clipTime or 0) elseif reload then a.reloadTime else a.boltTime
	local time = whole * (u1 - u0)
	if time <= 0 then
		return
	end
	local auto = action == "Auto"
	-- a box swapped whole (Config/Firing.BoxCycle); `out` "Open": the bolt held back until the plunger lets it go
	local box = reload and w.ammo.clip == "Box"
	local heldOpen = box and out == "Open"
	local turn, travel = math.rad(a.turn), a.travel * s[3]
	local cycle = if two
		then Cfg.ReloadCycleTwo
		elseif box then Cfg.BoxCycle
		elseif reload then Cfg.ReloadCycle
		elseif auto then Cfg.AutoCycle
		else (a.cycle or Cfg.BoltCycle) :: any
	local en = w.ammo.clip == "Enbloc"
	local rise = Cfg.ClipRise * s[2]
	-- the bolt: the hand reaches the handle (reload), turns it up, pulls it back; pushes it forward once the case is out
	-- (Bolt) or the hand is back on it (Reload), turns it down
	local reach = cycle.reach or 0
	local fwdFrom = if reload then cycle.knob else (cycle.hold or cycle.back) -- (a pump rests back until `hold`)
	local openAt = (reach + cycle.up) / 2
	local t0 = os.clock()
	-- what already happened before `from` doesn't happen again
	local opened, ejected = u0 > openAt, u0 > cycle.back
	local seated, closed = reload and u0 > (cycle.clip2 or cycle.clip), u0 > cycle.forward
	local firstIn = not two or u0 > cycle.clip -- (two chargers: the first one's sound)
	local flungAt = (cycle.knob or 0) + 0.02 -- the bolt starting forward strips the empty clip off the guides
	-- a pump gun: the shell on the carrier lifts to the bore and goes into the chamber as the pump comes forward (only
	-- when one is fed: an action held open feeds nothing), the next one shows on the carrier after
	local feed = if not reload and u1 >= 1 then w.feed else nil
	local feedMid = (fwdFrom + cycle.forward) / 2
	local function pose(u: number)
		local up = smooth((u - reach) / (cycle.up - reach))
		local back = if heldOpen then 1 else smooth((u - cycle.up) / (cycle.back - cycle.up))
		local forward = smooth((u - fwdFrom) / (cycle.forward - fwdFrom))
		local down = smooth((u - cycle.forward) / (cycle.down - cycle.forward))
		local angle = turn * (up - down)
		local slide = travel * (back - forward)
		-- the last round fed: the empty en-bloc clip drops out the bottom as the bolt closes
		local clipY: number? = nil
		if not reload and en and magazine == 0 then
			local c = smooth((u - cycle.forward) / (cycle.down - cycle.forward))
			if u >= cycle.forward then
				clipY = -rise * c
			end
		end
		-- the bolt going back pushes the hammer down ahead of it, by where the bolt is (hammer.push)
		local cocked = if w.hammer then along(w.hammer.push, back) else back
		local shellAt: CFrame? = nil
		if feed then
			local lift = smooth((u - fwdFrom) / (feedMid - fwdFrom))
			local push = smooth((u - feedMid) / (cycle.forward - feedMid))
			shellAt = CFrame.new(0, feed.lift * s[2] * lift, -feed.push * s[3] * push)
		end
		for _, gun in GunFx.guns(character) do
			move(gun, "Bolt", CFrame.new(0, 0, slide) * CFrame.Angles(0, 0, angle))
			move(gun, "Pump", CFrame.new(0, 0, slide))
			if not reload and w.hammer then
				move(gun, "Hammer", hammerAt(w, cocked))
			end
			if shellAt and feed then
				for _, name in feed.parts do
					move(gun, name, shellAt)
					show(gun, name, u < cycle.forward)
				end
			end
			if clipY then
				move(gun, "Clip", CFrame.new(0, clipY, 0))
				if en then
					move(gun, "Rounds", CFrame.new(0, clipY, 0))
				end
			end
		end
	end

	if running[tool] then
		running[tool]()
	end
	cut[tool] = nil
	-- the reload's hands (both views) and its clip, one per gun showing (the body's, the viewmodel's)
	local tracks = playAction(character, weapon, action, u0)
	local props: { [BasePart]: Prop } = {}
	local own = character == Players.LocalPlayer.Character
	if reload and own then
		character:SetAttribute("Reloading", true) -- src/client/Viewmodel holds its hip turn still meanwhile
	end
	-- two chargers: the first one from grab to its push (flung as the hand goes for the second), then the second
	local second = { grab = cycle.grab2 or 0, set = cycle.set2 or 0, clip = cycle.clip2 or 0 }
	local passOf: { [BasePart]: number } = {}
	-- a box swap: the gun's own box (and its rounds) hidden from the drop until the fresh one is seated; the old one
	-- falls away, the fresh one rides in the right hand (under its bottom, as the animation brings the hand) from the
	-- pouch to the well's mouth, then goes up in
	local BOX_PARTS = { "Magazine", "Rounds", "Bullets" }
	-- (only the box rides in the hand: the top rounds sit up in the receiver, over it, and floated out of the box, user
	-- 2026-10-19; they show again once it is seated)
	local HELD_PARTS = { "Magazine" }
	local dropped = u0 > (cycle.drop or 0)
	local boxProps: { [BasePart]: { { part: BasePart, rel: CFrame } } } = {}
	local function boxes(u: number)
		local r = w.reload
		local away = u >= cycle.drop and u < cycle.seat
		local inHand = u >= cycle.grab and u < cycle.seat
		for _, gun in GunFx.guns(character) do
			local holder = gun.Parent
			if not holder then
				continue
			end
			if not dropped and u >= cycle.drop then
				local mag = holder:FindFirstChild("Magazine")
				if mag and mag:IsA("BasePart") then
					local v = Cfg.Box.drop
					fling(mag:Clone(), gun, mag.CFrame, Vector3.new(v[1], v[2], v[3]))
				end
			end
			for _, name in BOX_PARTS do
				show(gun, name, not away and (name == "Magazine" or magazine > 0))
			end
			local list = boxProps[gun]
			if inHand and not list then
				list = {}
				for _, name in HELD_PARTS do
					local p = holder:FindFirstChild(name)
					if p and p:IsA("BasePart") then
						local copy = p:Clone()
						copy:ClearAllChildren()
						copy.Name = "Held" .. name
						copy.Anchored, copy.CanCollide, copy.CanQuery, copy.CanTouch = true, false, false, false
						copy.CastShadow = false
						copy.Transparency, copy.LocalTransparencyModifier = 0, 0
						copy.Parent = holder
						table.insert(list, { part = copy, rel = gun.CFrame:ToObjectSpace(p.CFrame) })
					end
				end
				boxProps[gun] = list
			elseif not inHand and list then
				for _, p in list do
					p.part:Destroy()
				end
				boxProps[gun] = nil
				list = nil
			end
			if list then
				-- where the seated box would be moved to: the hand under it, then the well's mouth, then up in
				local rig = if holder:IsA("Tool") then holder.Parent else holder
				local hand = rig and rig:FindFirstChild("Right Arm") :: BasePart?
				-- (the body's hand holds it by its right side, the viewmodel's from under it: tools/animation/reload.luau)
				local bodyHand = holder:IsA("Tool") and r.boxSide ~= nil
				local g = (if bodyHand then r.boxSide else r.boxGrip) or r.clipTop
				local off = if bodyHand then Vector3.new(Cfg.Box.hand, 0, 0) else Vector3.new(0, -Cfg.Box.hand, 0)
				local held = gun.CFrame:PointToWorldSpace(Vector3.new(g[1] * s[1], g[2] * s[2], g[3] * s[3]) + off)
				local mouth = gun.CFrame.UpVector * (r.entry * s[2])
				local shift: Vector3
				if u < cycle.set then
					local inHandAt = if hand then hand.CFrame:PointToWorldSpace(FIST) - held else mouth
					local b = Cfg.Box.blend
					shift = inHandAt:Lerp(mouth, smooth((u - (cycle.set - b)) / b))
				else
					shift = mouth * (1 - smooth((u - cycle.set) / (cycle.seat - cycle.set)))
				end
				for _, p in list do
					p.part.CFrame = CFrame.new(shift) * gun.CFrame * p.rel
				end
			end
		end
		dropped = dropped or u >= cycle.drop
	end
	local function clips(u: number)
		if box then
			boxes(u)
			return
		end
		if not reload then
			return
		end
		local pass = if two and u >= (cycle.clip + cycle.grab2) / 2 then 2 else 1
		local C = if pass == 2 then second else cycle
		local flingAt = if two and pass == 1 then cycle.fling else flungAt
		local holding = u >= C.grab and (not en or u < C.clip)
		for _, gun in GunFx.guns(character) do
			local prop = props[gun]
			if prop and passOf[gun] ~= pass then
				dropProp(prop) -- (the first charger is gone: a fresh one for the second)
				prop = nil
				props[gun] = nil
			end
			if holding and not prop then
				prop = makeProp(gun, weapon)
				if prop then
					props[gun] = prop
					passOf[gun] = pass
				end
			end
			if prop and #prop.parts > 0 then
				if not holding then
					dropProp(prop) -- the en-bloc clip is in: the gun's own clip shows from here
				elseif not en and u >= flingAt and not prop.flung then
					prop.flung = true
					for _, p in prop.parts do
						if not p.round then
							fling(p.part:Clone(), gun, p.part.CFrame, Vector3.new(4, 9, 1))
						end
					end
					dropProp(prop)
				else
					poseProp(prop, weapon, u, C)
				end
			end
		end
	end
	local function finish()
		for _, prop in props do
			dropProp(prop)
		end
		for gun, list in boxProps do
			for _, p in list do
				p.part:Destroy()
			end
			for _, name in BOX_PARTS do
				show(gun, name, name == "Magazine" or magazine > 0)
			end
		end
		table.clear(boxProps)
		if reload and own then
			character:SetAttribute("Reloading", nil)
		end
	end

	pose(u0)
	clips(u0)
	-- (whether the viewmodel was in view: playAction gave it its arms if it was)
	local shown = own and viewmodelAnimator() ~= nil
	local conn: RBXScriptConnection
	local function stop()
		conn:Disconnect()
		running[tool] = nil
		for _, t in tracks do
			if t.IsPlaying then
				t:Stop(0.1)
			end
		end
		finish()
	end
	conn = RunService.RenderStepped:Connect(function()
		local u = math.min(u0 + (os.clock() - t0) / time * (u1 - u0), u1)
		local gun = GunFx.visible(character)
		if not character.Parent or not gun or tool.Parent ~= character then
			-- put away (or gone) midway: stop here, keep the rest for when it's drawn again
			stop()
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
		-- back in first person midway (the action started in third person, or the view went out and back): the
		-- viewmodel's arms carry on from here
		if own then
			local vm = viewmodelAnimator()
			if vm and not shown and u < u1 then
				local id = firstAction(character, weapon, action)
				if id ~= 0 then
					local t = track(vm, id)
					t:Play(0)
					t.TimePosition = u * whole
					if not table.find(tracks, t) then
						table.insert(tracks, t)
					end
				end
			end
			shown = vm ~= nil
		end
		pose(u)
		clips(u)
		-- the mechanism's sounds on the body's gun: the viewmodel's goes out of the DataModel when the view leaves first
		-- person, which cut a sound playing on it short (user 2026-10-20)
		local ear = GunFx.guns(character)[1] or gun
		if not opened and u >= openAt then
			opened = true
			if not auto then -- (the shot covers a semi-automatic's own action)
				GunFx.sound(ear, "BoltOpen")
			end
		end
		if not ejected and u >= cycle.back then
			ejected = true
			if out == "Casing" then
				eject(gun, weapon)
			end
		end
		if two and not firstIn and u >= cycle.clip then
			firstIn = true
			GunFx.sound(ear, "ClipIn")
		end
		if reload and not seated and u >= (cycle.clip2 or cycle.clip) then
			seated = true
			GunFx.sound(ear, "ClipIn")
			GunFx.loadout(character, weapon, magazine) -- the rounds are in (an en-bloc clip with them)
		end
		if not closed and u >= cycle.forward then
			closed = true
			if not auto then
				GunFx.sound(ear, "BoltClose")
			end
		end
		if u >= u1 then
			conn:Disconnect()
			running[tool] = nil
			finish()
			if u1 < 1 then
				-- stopped short (a bolt held open on an empty rifle): the hand lets go and goes back to the grip
				for _, t in tracks do
					if t.IsPlaying then
						t:Stop(0.25)
					end
				end
			end
			if u1 >= 1 then -- closed: every part back at rest (a bolt held open stays back)
				for _, g in GunFx.guns(character) do
					move(g, "Bolt", CFrame.identity)
					move(g, "Pump", CFrame.identity)
					move(g, "Clip", CFrame.identity)
					move(g, "Rounds", CFrame.identity)
					for _, name in if w.feed then w.feed.parts else {} do
						move(g, name, CFrame.identity)
					end
				end
			end
			GunFx.loadout(character, weapon, magazine)
		end
	end)
	running[tool] = stop
end

-- ---- a revolver (ammo.clip "Gate": the Nagant; Config/Weapons `revolver`; user 2026-10-28) ----
-- The chambers keep their place on the cylinder; which hold a live round is told by the count alone: at rest the one on
-- the bore and the next ones round counter-clockwise (seen from behind) are live, so a shot turns the cylinder one
-- chamber clockwise and the next live one comes onto the bore. A chamber's round (its own part, chamber j = (1 - k) mod
-- n for Round k) shows while it is live, so the cylinder shows how many are left.
local function chamber(k: number, n: number): number
	return (1 - k) % n
end

-- the rounds of chambers from..from + count - 1 shown, the rest hidden (fired cases and empty chambers alike)
local function showDrum(gun: BasePart, rv: any, from: number, count: number)
	local n = #rv.rounds
	for k, name in rv.rounds do
		local j = chamber(k, n)
		local live = j >= from and j < from + count
		show(gun, name, live)
		if rv.bullets then -- (its bullet with it)
			show(gun, rv.bullets[k], live)
		end
	end
end

-- the cylinder (and everything turning with it) `steps` chambers clockwise from behind (about gun Z, -: clockwise)
local function turnDrum(gun: BasePart, rv: any, steps: number)
	local turn = CFrame.Angles(0, 0, -2 * math.pi / #rv.rounds * steps)
	for _, name in rv.turns do
		move(gun, name, turn)
	end
end

-- The cylinder at rest with `live` rounds in it (drawn again, after a load, someone else's gun resynced).
function GunFx.drum(character: Model, weapon: string, live: number)
	local rv = W[weapon].revolver
	if not rv then
		return
	end
	for _, gun in GunFx.guns(character) do
		turnDrum(gun, rv, 0)
		move(gun, "Gate", CFrame.identity)
		move(gun, "Rod", CFrame.identity)
		showDrum(gun, rv, 0, live)
	end
end

-- A double-action pull, shown as the shot goes (it fires on the click): the trigger comes back from the pull, the
-- hammer falls from full cock, and the cylinder turns the next chamber onto the bore; `live`: rounds left after it.
local turning: { [Tool]: RBXScriptConnection } = setmetatable({}, { __mode = "k" }) :: any
function GunFx.revolve(character: Model, weapon: string, live: number)
	local w = W[weapon]
	local rv = w.revolver
	local tool = character:FindFirstChildOfClass("Tool")
	if not rv or not tool then
		return
	end
	local was = turning[tool]
	if was then
		was:Disconnect()
	end
	local T = 0.8 * (w.action.fireTime or Cfg.PistolFireTime)
	local t0 = os.clock()
	local hammer, trigger = math.rad(rv.hammer), math.rad(rv.trigger)
	local function pose(u: number)
		for _, gun in GunFx.guns(character) do
			move(gun, "Hammer", CFrame.Angles(hammer * (1 - smooth(u / 0.15)), 0, 0))
			move(gun, "Trigger", CFrame.Angles(-trigger * (1 - smooth(u)), 0, 0))
			if u < 1 then
				turnDrum(gun, rv, smooth(u / 0.6))
				showDrum(gun, rv, 1, live) -- (the fired chamber's case hidden, the next ones coming round)
			else
				turnDrum(gun, rv, 0)
				showDrum(gun, rv, 0, live)
			end
		end
	end
	pose(0)
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local u = math.min((os.clock() - t0) / T, 1)
		if not character.Parent or tool.Parent ~= character then
			u = 1
		end
		pose(u)
		if u >= 1 then
			conn:Disconnect()
			if turning[tool] == conn then
				turning[tool] = nil
			end
		end
	end)
	turning[tool] = conn
end

-- The gate, the rod and the cylinder `e` seconds into loading single rounds (GunFx.load's clock: O to open, R a round,
-- the gate shut over CL from cs; `live` rounds in it at the start, `rounds` going in, `pressed` in so far). The gate
-- opens with the cylinder turned to the first empty chamber; each round, the rod (pulled forward out of the cylinder)
-- swings over to the gate's chamber and punches the fired case out through it, swings back, the round goes in, and the
-- cylinder turns on a chamber for the next; at the end the cylinder turns on round to rest and the gate shuts.
local function loadDrum(
	gun: BasePart,
	w: any,
	e: number,
	live: number,
	rounds: number,
	pressed: number,
	O: number,
	R: number,
	cs: number,
	CL: number
)
	local rv = w.revolver
	local n = #rv.rounds
	local s = w.scale
	local first = (live + rv.gateChamber) % n -- turns bringing the first empty chamber to the gate
	local last = first + math.max(rounds - 1, 0)
	local home = math.ceil(last / n) * n -- (a whole number of turns: the same cylinder at rest)
	local steps, gate, rodOut, side, push = 0, 0, 0, 0, 0
	if e < O then
		steps = first * smooth(e / O)
		gate = smooth(e / (0.6 * O))
		rodOut = smooth(e / O)
	elseif e < cs then
		local i = math.floor((e - O) / R)
		local q = ((e - O) % R) / R
		steps = first + i + (if i > 0 then smooth(q / 0.1) - 1 else 0)
		gate, rodOut = 1, 1
		side = smooth((q - 0.1) / 0.08) - smooth((q - 0.46) / 0.06)
		push = smooth((q - 0.18) / 0.18) - smooth((q - 0.36) / 0.1)
	else
		local k = smooth((e - cs) / (0.6 * CL))
		steps = last + (home - last) * k
		gate = 1 - smooth((e - cs - 0.3 * CL) / (0.7 * CL))
		rodOut = 1 - k
	end
	turnDrum(gun, rv, steps)
	move(gun, "Gate", CFrame.Angles(0, 0, -math.rad(rv.gateOpen) * gate))
	local r = rv.rod
	local z = (-r.out * rodOut + (r.out + r.through) * push) * s[3]
	move(gun, "Rod", CFrame.new(r.side[1] * s[1] * side, r.side[2] * s[2] * side, z))
	showDrum(gun, rv, 0, live + pressed)
end

-- ---- loading single rounds (Config/Firing.Single; tools/animation/single.luau; user 2026-10-13) ----
-- Played by its own clock: e seconds since the load began. The bolt opens over the first 80% of `open` (on the
-- reload's shares), stays back while rounds go in (one every `round`), and closes over `close`; the animation's track
-- is held at speed 0 and its time set every frame (the one-round stretch played again for each round); a round shows
-- in the right hand from the moment it is taken until it is pushed in. `rounds` is how many go in (nil: until the
-- magazine is full, `room`); GunFx.loadStop fixes it when the player clicks.
type LoadRun = { rounds: number? }
local loads: { [Tool]: LoadRun } = setmetatable({}, { __mode = "k" }) :: any

local ROUND_SIDE, FIRST_ROUND_SIDE = 0.55, 0.85 -- the round pinched beside the hand (tools/animation/single.luau)

-- a loose round for the hand: the gun's spent-case template with a bullet tip; a pump gun's shell: copies of its own
-- shell parts (Config/Weapons feed)
local function makeRound(gun: BasePart, weapon: string): { BasePart }?
	local holder = gun.Parent
	local feed = W[weapon].feed
	if holder and feed then
		local parts = {}
		for _, name in feed.parts do
			local t = holder:FindFirstChild(name)
			if t and t:IsA("BasePart") then
				local c = t:Clone()
				c:ClearAllChildren()
				c.Name = "Held" .. name
				c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow = true, false, false, false, false
				c.Transparency, c.LocalTransparencyModifier = 0, 0
				c:SetAttribute("Rel", t.CFrame:ToObjectSpace((holder:FindFirstChild(feed.parts[1]) :: BasePart).CFrame))
				c.Parent = holder
				table.insert(parts, c)
			end
		end
		return if #parts > 0 then parts else nil
	end
	-- (a revolver's: its whole round, Config/Weapons `revolver.loose`)
	local rv = W[weapon].revolver
	local revolver = rv ~= nil
	local case = holder and holder:FindFirstChild(if rv then rv.loose else "Casing")
	if not case or not case:IsA("BasePart") then
		return nil
	end
	local body = case:Clone()
	body:ClearAllChildren()
	body.Name = "HeldRound"
	body.Anchored, body.CanCollide, body.CanQuery, body.CanTouch, body.CastShadow = true, false, false, false, false
	body.Transparency, body.LocalTransparencyModifier = 0, 0
	body.Parent = holder
	if revolver then
		return { body }
	end
	local tip = Instance.new("Part")
	tip.Name = "HeldRoundTip"
	tip.Shape = Enum.PartType.Ball
	tip.Material = Enum.Material.SmoothPlastic
	local bullets = holder:FindFirstChild("Bullets")
	tip.Color = if bullets and bullets:IsA("BasePart") then bullets.Color else Color3.fromRGB(184, 115, 72)
	local d = math.min(body.Size.X, body.Size.Y) * 0.85
	tip.Size = Vector3.new(d, d, d)
	tip.Anchored, tip.CanCollide, tip.CanQuery, tip.CanTouch, tip.CastShadow = true, false, false, false, false
	tip.Parent = holder
	return { body, tip }
end

local function placeRound(parts: { BasePart }, centre: CFrame)
	local body, tip = parts[1], parts[2]
	body.CFrame = centre
	if not tip then
		return
	end
	local rel = tip:GetAttribute("Rel")
	if typeof(rel) == "CFrame" then -- a shell's head, where it sits on the hull
		tip.CFrame = centre * rel:Inverse()
	else
		tip.CFrame = centre * CFrame.new(0, 0, -body.Size.Z / 2)
	end
end

function GunFx.loadStop(character: Model, rounds: number)
	local tool = character:FindFirstChildOfClass("Tool")
	local run = tool and loads[tool]
	if run and not run.rounds then
		run.rounds = rounds
	end
end

function GunFx.load(character: Model, weapon: string, out: string?, from: number, rounds: number?, room: number)
	local w = W[weapon]
	local tool = character:FindFirstChildOfClass("Tool")
	local single = w.single
	if not tool or not single then
		return
	end
	local SI, C = Cfg.Single, Cfg.SingleCycle
	local O, R, CL = SI.open, SI.round, SI.close
	local s = w.scale
	local turn, travel = math.rad(w.action.turn), w.action.travel * s[3]
	O, R, CL = single.open or O, single.round or R, single.close or CL
	-- loose shells (a pump gun): the action stays shut, unless it was held open ("Open"): then it closes at the end
	-- a revolver's gate (Config/Weapons `revolver`): nothing to open either, the gate and the rod instead (loadDrum)
	local rv = w.revolver
	local live = W[weapon].ammo.capacity - room -- (a revolver: rounds in it at the start)
	local loose = w.ammo.clip == "Loose" or rv ~= nil
	local wasOpen = loose and out == "Open"
	if loose then
		out = nil -- nothing comes out of the chamber
	end
	local run: LoadRun = { rounds = rounds }
	local function plan(): number
		return run.rounds or room
	end
	local function closeStart(): number
		return O + plan() * R
	end
	local B = 0.8 * O -- the bolt is back by here
	local openAt = B * ((C.reach + C.up) / 2) / C.back
	local shutAt = CL * (C.forward - C.clip) / (1 - C.clip) -- into the closing stretch: the bolt goes home
	local t0 = os.clock() - from
	local opened, ejected = from > openAt, from > B
	local closed = from > closeStart() + shutAt
	local pressed = math.clamp(math.floor((from - O) / R), 0, plan())
	local punched = if from >= O then math.min(math.floor((from - O) / R + (1 - 0.36)), plan()) else 0

	if running[tool] then
		running[tool]()
	end
	cut[tool] = nil
	loads[tool] = run
	local own = character == Players.LocalPlayer.Character
	if own then
		character:SetAttribute("Reloading", true)
	end
	-- the arms: the body's (ours, or a soldier no player owns) and the viewmodel's, driven frame by frame
	local tracks: { AnimationTrack } = {}
	local function start(animator: Animator?, id: number)
		if not animator or id == 0 then
			return
		end
		local t = track(animator, id)
		t:Play(0.12)
		t:AdjustSpeed(0)
		table.insert(tracks, t)
	end
	if own or not Players:GetPlayerFromCharacter(character) then
		start(animatorOf(character), single.body)
	end
	if own then
		start(viewmodelAnimator(), single.firstPerson)
	end
	local roundsHeld: { [BasePart]: { BasePart } } = {}

	local function pose(e: number)
		local cs = closeStart()
		local angle, slide
		if loose then
			angle = 0
			slide = if wasOpen then travel * (1 - smooth((e - cs) / CL)) else 0
		elseif e < cs then
			local u = math.min(e / B, 1) * C.back
			angle = turn * smooth((u - C.reach) / (C.up - C.reach))
			slide = travel * smooth((u - C.up) / (C.back - C.up))
		else
			local u = C.clip + (e - cs) / CL * (1 - C.clip)
			angle = turn * (1 - smooth((u - C.forward) / (C.down - C.forward)))
			slide = travel * (1 - smooth((u - C.knob) / (C.forward - C.knob)))
		end
		if rv then
			local k = math.clamp(math.floor((e - O) / R), 0, plan())
			for _, gun in GunFx.guns(character) do
				loadDrum(gun, w, e, live, plan(), k, O, R, cs, CL)
			end
		end
		local animT = if e < O then e elseif e < cs then O + (e - O) % R else O + R + (e - cs)
		for _, t in tracks do
			t.TimePosition = math.min(animT, t.Length)
		end
		-- the round in the hand: taken at 42% of its stretch, pushed in over the last 20%
		local i = math.floor((e - O) / R)
		local q = ((e - O) % R) / R
		local showing = e >= O and e < cs and i < plan() and q >= 0.42
		for _, gun in GunFx.guns(character) do
			move(gun, "Bolt", CFrame.new(0, 0, slide) * CFrame.Angles(0, 0, angle))
			move(gun, "Pump", CFrame.new(0, 0, slide))
			local parts = roundsHeld[gun]
			if showing and not parts then
				parts = makeRound(gun, weapon)
				if parts then
					roundsHeld[gun] = parts
				end
			end
			if parts then
				for _, p in parts do
					p.Transparency = if showing then 0 else 1
				end
				if showing then
					local holder = gun.Parent :: Instance
					local rig = if holder:IsA("Tool") then holder.Parent else holder
					local hand = rig and rig:FindFirstChild("Right Arm") :: BasePart?
					local side = if holder:IsA("Tool") then ROUND_SIDE else FIRST_ROUND_SIDE
					local seat = gun.CFrame
						* CFrame.new(single.seat[1] * s[1], single.seat[2] * s[2], single.seat[3] * s[3])
					local held = seat
					if hand then
						held = CFrame.new(hand.CFrame:PointToWorldSpace(FIST) - gun.CFrame.RightVector * side)
							* gun.CFrame.Rotation
					end
					placeRound(parts, held:Lerp(seat, smooth((q - 0.8) / 0.2)))
				end
			end
		end
	end
	local function finish()
		for _, parts in roundsHeld do
			for _, p in parts do
				p:Destroy()
			end
		end
		table.clear(roundsHeld)
		if loads[tool] == run then
			loads[tool] = nil
		end
		if own then
			character:SetAttribute("Reloading", nil)
		end
	end
	local conn: RBXScriptConnection
	local function stop()
		conn:Disconnect()
		running[tool] = nil
		for _, t in tracks do
			if t.IsPlaying then
				t:Stop(0.15)
			end
		end
		finish()
	end
	pose(from)
	conn = RunService.RenderStepped:Connect(function()
		local e = os.clock() - t0
		local gun = GunFx.visible(character)
		if not character.Parent or not gun or tool.Parent ~= character then
			-- put away: stop here; drawn again it carries on (the round in the hand still goes in)
			local k = run.rounds or (if e <= O then 0 else math.min(room, math.ceil((e - O) / R)))
			stop()
			cut[tool] = {
				weapon = weapon,
				action = "Load",
				out = if wasOpen then "Open" elseif ejected then nil else out,
				magazine = room,
				from = e,
				to = k,
			}
			return
		end
		local cs = closeStart()
		local total = cs + CL
		e = math.min(e, total)
		-- in first person the viewmodel's arms load too, even if the load began in third person or the view went out
		-- and back (out of view its tracks were stopped); pose sets their time
		local vm = if own and single.firstPerson ~= 0 then viewmodelAnimator() else nil
		if vm then
			local t = track(vm, single.firstPerson)
			if not t.IsPlaying then
				t:Play(0)
				t:AdjustSpeed(0)
				if not table.find(tracks, t) then
					table.insert(tracks, t)
				end
			end
		end
		pose(e)
		local ear = GunFx.guns(character)[1] or gun -- (the mechanism's sounds: as in GunFx.cycle)
		if not opened and e >= openAt then
			opened = true
			if not loose or rv then -- (a revolver: the gate)
				GunFx.sound(ear, "BoltOpen")
			end
		end
		-- a revolver: the rod punches each fired case out through the gate
		local p = if rv and e >= O then math.min(math.floor((e - O) / R + (1 - 0.36)), plan()) else 0
		while rv and punched < p do
			punched += 1
			eject(gun, weapon)
		end
		if not ejected and e >= B then
			ejected = true
			if out then
				eject(gun) -- the spent case, or the live round that was in the chamber
			end
		end
		local k = math.clamp(math.floor((e - O) / R), 0, plan())
		while pressed < k do
			pressed += 1
			GunFx.sound(ear, "ClipIn")
		end
		if not closed and e >= cs + shutAt then
			closed = true
			if not loose or wasOpen or rv then
				GunFx.sound(ear, "BoltClose")
			end
		end
		if e >= total then
			stop()
			for _, g in GunFx.guns(character) do
				move(g, "Bolt", CFrame.identity)
				move(g, "Pump", CFrame.identity)
			end
			GunFx.loadout(character, weapon, 1)
			GunFx.drum(character, weapon, live + plan())
		end
	end)
	running[tool] = stop
end

return GunFx
