--!strict
-- A gun's barrel warming as it fires (Config/Artillery.Guns `heat` and Heat, Rules/Artillery heatStep / heatGlow; user
-- 2026-10-29: "make the barrel get warmer from the tip as you hold it (steam a little too)", the MG and the field gun):
-- on every client, from the shots it sees (src/client/Artillery calls shot() for each). Glowing bands round the
-- barrel's first `length` studs from the muzzle, lit from the tip back as it warms, riding the barrel as it is posed;
-- past `steam` a wisp of steam rising off the tip, and the tip's light on what is round it. The bands are this
-- client's own (a folder in the Workspace, not in the gun's model, so its jolt and the server never touch them); none
-- while cold.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Artillery)
local Rules = require(Shared.Rules.Artillery)

local BarrelHeat = {}

type Bands = { parts: { Part }, offsets: { CFrame }, steam: ParticleEmitter, light: PointLight }
type State = { heat: number, bands: Bands? }

local states: { [Model]: State } = {}
local folder: Folder? = nil

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function holder(): Folder
	if not folder or not folder.Parent then
		local f = Instance.new("Folder")
		f.Name = "BarrelHeat"
		f.Parent = workspace
		folder = f
	end
	return folder :: Folder
end

-- the bands for a gun, laid round its barrel from its Bore (the disc set `boreCentre` back in the muzzle) at its rest:
-- `rest` the posed parts' rest places in the pivot's frame (src/client/Artillery's Pose)
local function build(gun: any, barrel: BasePart, bore: BasePart, rest: { [BasePart]: CFrame }): Bands?
	local H = gun.heat
	local barrelRest, boreRest = rest[barrel], rest[bore]
	if not barrelRest or not boreRest then
		return nil
	end
	local radius = H.radius * math.max(bore.Size.X, bore.Size.Y) / 2
	local seg = H.length / H.segments
	local tip = boreRest.Position - Vector3.new(0, 0, gun.boreCentre) -- (the muzzle points -Z)
	local parts, offsets = {}, {}
	for i = 1, H.segments do
		local p = Instance.new("Part")
		p.Name = "Band" .. i
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(seg, radius * 2, radius * 2)
		p.Material = Enum.Material.Neon
		p.Transparency = 1
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		-- (a cylinder's axis is its X: turned onto the bore)
		local at = CFrame.new(tip + Vector3.new(0, 0, seg * (i - 0.5))) * CFrame.Angles(0, math.pi / 2, 0)
		offsets[i] = barrelRest:Inverse() * at
		p.Parent = holder()
		parts[i] = p
	end
	local S = Cfg.Heat.steam
	local a = Instance.new("Attachment")
	a.Parent = parts[1]
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.Color = ColorSequence.new(rgb(S.color))
	e.LightEmission = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, S.size), NumberSequenceKeypoint.new(1, S.grow) })
	e.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, S.transparency), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(S.life[1], S.life[2])
	e.Speed = NumberRange.new(S.speed[1], S.speed[2])
	e.SpreadAngle = Vector2.new(180, 180) -- (every which way)
	e.Acceleration = Vector3.new(0, S.rise, 0)
	e.Drag = S.drag
	e.RotSpeed = NumberRange.new(-S.spin, S.spin)
	e.Rotation = NumberRange.new(0, 360)
	e.Parent = a
	-- the tip's own glow on what is round it, as hot (Heat.light)
	local light = Instance.new("PointLight")
	light.Color = rgb(Cfg.Heat.hot)
	light.Range = Cfg.Heat.light.range
	light.Brightness = 0
	light.Shadows = false
	light.Parent = parts[1]
	return { parts = parts, offsets = offsets, steam = e, light = light }
end

local function clear(s: State)
	if s.bands then
		for _, p in s.bands.parts do
			p:Destroy()
		end
		s.bands = nil
	end
end

-- `shots` more shots from `model`
function BarrelHeat.shot(model: Model, gun: any, shots: number)
	local H = gun.heat
	if not H then
		return
	end
	local s = states[model]
	if not s then
		s = { heat = 0 }
		states[model] = s
		model.Destroying:Connect(function()
			local gone = states[model]
			if gone then
				clear(gone)
			end
			states[model] = nil
		end)
	end
	s.heat = Rules.heatStep(s.heat, shots, 0, H.per, H.cool)
end

-- every frame, after `model` has been posed: cools it and lays its bands on its barrel as posed now
function BarrelHeat.step(
	model: Model,
	gun: any,
	dt: number,
	named: { [string]: BasePart },
	rest: { [BasePart]: CFrame }
)
	local s = states[model]
	local H = gun.heat
	if not s or not H then
		return
	end
	s.heat = Rules.heatStep(s.heat, 0, dt, H.per, H.cool)
	if s.heat <= 0 then
		clear(s)
		return
	end
	local barrel, bore = named.Barrel, named.Bore
	if not barrel or not bore then
		return
	end
	if not s.bands then
		s.bands = build(gun, barrel, bore, rest)
	end
	local b = s.bands
	if not b then
		return
	end
	local C = Cfg.Heat
	for i, p in b.parts do
		-- (eased in: a band only just past its start barely shows)
		local glow = Rules.heatGlow(s.heat, i, H.segments, C.lead) ^ C.curve
		p.CFrame = barrel.CFrame * b.offsets[i]
		p.Transparency = 1 - C.glow * glow
		p.Color = rgb(C.cold):Lerp(rgb(C.hot), glow)
	end
	b.light.Brightness = C.light.brightness * s.heat ^ C.curve
	b.steam.Rate = if s.heat > H.steam then H.steamRate * (s.heat - H.steam) / (1 - H.steam) else 0
end

return BarrelHeat
