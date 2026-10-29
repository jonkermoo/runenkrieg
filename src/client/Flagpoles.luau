--!strict
-- The capture-point flags (Config/Flagpole, Rules/Flagpole; FLAGPOLE.md, user 2026-10-27), this client's side of the
-- poles src/server/Flagpoles stands: on each pole the holder's flag (Config/Uniforms.Kits[kit].flag.pole, split over 4
-- hinged strips) eased toward the sector's replicated control (Workspace.Frontline.<sector>.Control): at the top for
-- full control, lowered as it is lost, gone at neutral (a bare pole, the halyard slack), the other side's rising as they
-- gain it. It flies downwind along workspace.GlobalWind and flaps harder in stronger wind and while contested; a bullet
-- through or near it jolts it (Flagpoles.shot, from src/client/Impacts), a blast nearby whips it (Flagpoles.blast,
-- from src/client/Vfx/Blast). The zone stakes carry a rag in the holder's colour (bare at neutral) and hide where
-- their ground has been dug away. Sounds (3D at the pole): the cloth's flap, the halyard while the flag moves, a trench
-- whistle when the point is taken. Full rate near the camera, slower further off, frozen far away.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Flagpole)
local HudCfg = require(Shared.Config.ModeHud)
local Palette = require(Shared.Config.Palette)
local U = require(Shared.Config.Uniforms)
local Rules = require(Shared.Rules.Flagpole)

local Flagpoles = {}

local COLORS = Palette.Flagpole :: any
local F, FL = Cfg.Flag, Cfg.Flap

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true

type Stake = { part: BasePart, rag: BasePart, footY: number }
type Pole = {
	model: Model,
	scale: number,
	height: number,
	w: number,
	h: number,
	axis: Vector3, -- the pole's foot
	strips: { BasePart },
	images: { ImageLabel },
	rope: BasePart,
	stakes: { Stake },
	shown: number, -- the control shown (eased toward the replicated one)
	kit: string?, -- whose flag the strips carry
	up: boolean, -- the flag shown
	owner: string?,
	ragKit: string?, -- whose rags the stakes carry
	extra: number, -- jolt / whip degrees, decaying
	extraDecay: number,
	last: number, -- when it last moved
	nextCheck: number,
	sounds: { [string]: Sound },
}

local poles: { [Model]: Pole } = {}

local function flagImage(kit: string?): string
	local k = kit and U.Kits[kit]
	return if k and k.flag then `rbxassetid://{k.flag.pole}` else ""
end

local function part(name: string, size: Vector3, color: Color3, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = parent
	return p
end

local function sound(name: string, s: any, parent: Instance, looped: boolean): Sound?
	if not s.id then
		return nil
	end
	local snd = Instance.new("Sound")
	snd.Name = name
	snd.SoundId = `rbxassetid://{s.id}`
	snd.Volume = s.volume
	snd.RollOffMinDistance = s.min
	snd.RollOffMaxDistance = s.max
	snd.RollOffMode = Enum.RollOffMode.InverseTapered
	snd.Looped = looped
	snd.Parent = parent
	return snd
end

local function build(model: Model): Pole?
	local pole = model.PrimaryPart or model:FindFirstChild("Pole") :: BasePart?
	if not pole then
		return nil
	end
	local k = (model:GetAttribute("Scale") :: number?) or 1
	local hq = model:GetAttribute("HQ") == true
	local size = if hq then F.hqSize else F.size
	local w, h = size[1], size[2]
	local local_ = Instance.new("Folder")
	local_.Name = "Flag"
	local_.Parent = model
	local strips, images = {}, {}
	local sw = w / F.strips
	for i = 1, F.strips do
		local s = part(`Strip{i}`, Vector3.new(sw, h, F.thickness), Color3.new(1, 1, 1), local_)
		s.Transparency = 1
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local gui = Instance.new("SurfaceGui")
			gui.Face = face
			gui.LightInfluence = 1
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 32
			gui.Parent = s
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.Size = UDim2.fromScale(1, 1)
			-- (the back face shows the cloth from behind: the strips in the same order, mirrored by the face itself)
			img.ImageRectOffset = Vector2.new((i - 1) * F.image.strip[1], 0)
			img.ImageRectSize = Vector2.new(F.image.strip[1], F.image.strip[2])
			img.Visible = false
			img.Parent = gui
			table.insert(images, img)
		end
		strips[i] = s
	end
	local rope = part("Halyard", Vector3.new(Cfg.Rope.thickness, 1, Cfg.Rope.thickness), rgb(COLORS.Rope), local_)
	rope.CastShadow = false
	local stakes: { Stake } = {}
	local folder = model:FindFirstChild("Stakes")
	for _, st in if folder then folder:GetChildren() else {} do
		if st:IsA("BasePart") then
			local r = Cfg.Stakes.rag
			local rag = part("Rag", Vector3.new(r[1], r[2], r[3]), Color3.new(1, 1, 1), local_)
			rag.CastShadow = false
			rag.Transparency = 1
			rag.CFrame = st.CFrame * CFrame.new(r[1] / 2, Cfg.Stakes.ragAt - st.Size.Y / 2, 0)
			table.insert(stakes, { part = st, rag = rag, footY = st.Position.Y - st.Size.Y / 2 })
		end
	end
	local foot = pole.Position - Vector3.new(0, pole.Size.Y / 2, 0)
	local p: Pole = {
		model = model,
		scale = k,
		height = Cfg.Pole.height * k,
		w = w,
		h = h,
		axis = foot,
		strips = strips,
		images = images,
		rope = rope,
		stakes = stakes,
		shown = 0,
		kit = nil,
		up = false,
		owner = nil,
		ragKit = nil,
		extra = 0,
		extraDecay = 0,
		last = os.clock(),
		nextCheck = 0,
		sounds = {},
	}
	local at = Instance.new("Attachment")
	at.Name = "FlagSound"
	at.Position = Vector3.new(0, p.height * 0.6 - pole.Size.Y / 2, 0)
	at.Parent = pole
	for name, s in Cfg.Sounds do
		local snd = sound(name, s, at, name ~= "Whistle")
		if snd then
			p.sounds[name] = snd
		end
	end
	return p
end

local function setKit(p: Pole, kit: string?)
	if p.kit == kit then
		return
	end
	p.kit = kit
	local img = flagImage(kit)
	for _, i in p.images do
		i.Image = img
	end
	-- (the cloth's edges in the flag's main colour)
	local c = kit and COLORS.Rags[kit]
	for _, s in p.strips do
		s.Color = if c then rgb(c) else Color3.new(1, 1, 1)
	end
end

-- the pole's radius at height y over its foot
local function radiusAt(p: Pole, y: number): number
	local P = Cfg.Pole
	return (P.footRadius + (P.topRadius - P.footRadius) * math.clamp(y / p.height, 0, 1)) * p.scale
end

local function pose(p: Pole, now: number, contested: boolean)
	local side, share = Rules.flag(p.shown)
	local up = share > 0 and p.kit ~= nil
	if up ~= p.up then
		p.up = up
		for _, s in p.strips do
			s.Transparency = if up then 0 else 1
		end
		for _, i in p.images do
			i.Visible = up
		end
	end
	local strength, dx, dz = Rules.wind(workspace.GlobalWind.X, workspace.GlobalWind.Z, FL)
	local top = Rules.top(share, p.height, p.h, F)
	local axisTop = p.axis + Vector3.new(0, top - p.h / 2, 0)
	local dir = Vector3.new(dx, 0, dz)
	-- the hoist: on the pole's downwind side, the flag's local +X running downwind
	local base = CFrame.fromMatrix(axisTop, dir, Vector3.yAxis)
	local hoist = base
		* CFrame.new(radiusAt(p, top) + F.gap, 0, 0)
		* CFrame.Angles(0, 0, -math.rad(Rules.droop(strength, FL)))
	if up then
		local cf = hoist
		local n = #p.strips
		for i, s in p.strips do
			local turn = Rules.flap(i, n, now, strength, contested, FL)
				+ p.extra * (i / n) * math.sin(now * FL.speed * 2.3 - i * FL.wave)
			cf = cf * CFrame.Angles(0, math.rad(turn), 0)
			s.CFrame = cf * CFrame.new(p.w / F.strips / 2, 0, 0)
			cf = cf * CFrame.new(p.w / F.strips, 0, 0)
		end
	end
	-- the halyard: from the cleat's height up to the top, just off the pole on the flag's side; slack (leaning) when bare
	local R = Cfg.Rope
	local low = p.axis + Vector3.new(0, 3.4 * p.scale, 0)
	local high = p.axis + Vector3.new(0, p.height, 0)
	local out = dir * (radiusAt(p, p.height * 0.5) + R.out)
	local mid = (low + high) / 2 + out
	local lean = if up then 0 else math.rad(R.slackLean)
	p.rope.Size = Vector3.new(R.thickness, (high - low).Magnitude, R.thickness)
	p.rope.CFrame = CFrame.fromMatrix(mid, dir:Cross(Vector3.yAxis), Vector3.yAxis) * CFrame.Angles(lean, 0, 0)
	return side
end

local function rags(p: Pole, owner: string?, front: Instance)
	local kit = if owner == "West" or owner == "East" then front:GetAttribute(owner) :: string? else nil
	if kit == p.ragKit then
		return
	end
	p.ragKit = kit
	local c = kit and COLORS.Rags[kit]
	for _, s in p.stakes do
		s.rag.Transparency = if c then 0 else 1
		if c then
			s.rag.Color = rgb(c)
		end
	end
end

local function digCheck(p: Pole, now: number)
	if now < p.nextCheck then
		return
	end
	p.nextCheck = now + Cfg.Stakes.recheck
	for _, s in p.stakes do
		local at = s.part.Position
		local hit = workspace:Raycast(at + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), terrainOnly)
		local gone = not hit or hit.Position.Y < s.footY + Cfg.Sink - Cfg.Stakes.dug
		local m = if gone then 1 else 0
		s.part.LocalTransparencyModifier = m
		s.rag.LocalTransparencyModifier = m
	end
end

local function update(p: Pole, front: Instance, now: number, dt: number, camPos: Vector3)
	local f = front:FindFirstChild(p.model.Name)
	if not f then
		return
	end
	local control = (f:GetAttribute("Control") :: number?) or 0
	local owner = f:GetAttribute("Owner") :: string?
	local west, east = (f:GetAttribute("West") :: number?) or 0, (f:GetAttribute("East") :: number?) or 0
	local contested = west > 0 and west == east
	-- taken: the trench whistle (not when a new match puts the sectors back: the flag is then far from the control)
	local taken = owner ~= p.owner and (owner == "West" or owner == "East") and p.owner ~= nil
	if taken and math.abs(p.shown - control) < 0.5 then
		local w = p.sounds.Whistle
		if w then
			w:Play()
		end
	end
	rags(p, owner, front)
	p.owner = owner
	local before = p.shown
	p.shown = Rules.ease(p.shown, control, F.ease, dt)
	local side = Rules.flag(p.shown)
	setKit(p, if side then front:GetAttribute(side) :: string? else nil)
	p.extra *= math.exp(-p.extraDecay * dt)
	-- sounds
	local strength = Rules.wind(workspace.GlobalWind.X, workspace.GlobalWind.Z, FL)
	local flap = p.sounds.Flap
	if flap then
		local on = side ~= nil
		if on and not flap.IsPlaying then
			flap:Play()
		elseif not on and flap.IsPlaying then
			flap:Stop()
		end
		flap.Volume = Cfg.Sounds.Flap.volume * math.clamp(0.4 + 0.6 * strength, 0, 1.5)
	end
	local hal = p.sounds.Halyard
	if hal then
		local moving = math.abs(p.shown - before) / math.max(dt, 1e-3) > Cfg.Sounds.Halyard.moving
		if moving and not hal.IsPlaying then
			hal:Play()
		elseif not moving and hal.IsPlaying then
			hal:Stop()
		end
	end
	-- the cloth: by distance
	local step = Rules.step((camPos - p.axis).Magnitude, Cfg.Lod)
	if step and now - p.last >= step then
		p.last = now
		pose(p, now, contested)
	end
	digCheck(p, now)
end

-- A bullet's line from `from` to `hit` (src/client/Impacts.shot): a flag it passed through or near jolts.
function Flagpoles.shot(from: Vector3?, hit: Vector3)
	if not from then
		return
	end
	for _, p in poles do
		local s = p.strips[2]
		if s and p.up then
			local c = s.Position
			local d = Rules.toSegment(from.X, from.Y, from.Z, hit.X, hit.Y, hit.Z, c.X, c.Y, c.Z)
			if d < Cfg.Jolt.radius + p.w / 2 then
				p.extra = math.max(p.extra, Cfg.Jolt.degrees)
				p.extraDecay = Cfg.Jolt.decay
			end
		end
	end
end

-- A blast of `kg` at `at` (src/client/Vfx/Blast): flags near it whip for a moment.
function Flagpoles.blast(at: Vector3, kg: number)
	for _, p in poles do
		local deg = Rules.whip(kg, (at - (p.axis + Vector3.new(0, p.height * 0.7, 0))).Magnitude, Cfg.Whip)
		if deg > p.extra then
			p.extra = deg
			p.extraDecay = Cfg.Whip.decay
		end
	end
end

function Flagpoles.start()
	local last = os.clock()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = now - last
		last = now
		local folder = workspace:FindFirstChild(Cfg.FolderName)
		local front = workspace:FindFirstChild(HudCfg.FrontlineFolder)
		for model in poles do
			if not model.Parent then
				poles[model] = nil
			end
		end
		if not folder or not front then
			return
		end
		local cam = workspace.CurrentCamera
		local camPos = if cam then cam.CFrame.Position else Vector3.zero
		for _, m in folder:GetChildren() do
			if m:IsA("Model") then
				local p = poles[m]
				if not p then
					p = build(m)
					if not p then
						continue
					end
					poles[m] = p
				end
				update(p :: Pole, front, now, dt, camPos)
			end
		end
	end)
end

return Flagpoles
