--!strict
-- Pools of effect pieces (Config/Vfx.Quality): attachments, beams, glowing parts, lights and particle emitters are
-- made once and reused, so firing never builds and destroys instances. Everything sits under one anchored "Hub"
-- part at the world origin (so an attachment's Position is its world position); a freed piece is hidden, not
-- destroyed, unless its pool is full.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Q = require(ReplicatedStorage:WaitForChild("Shared").Config.Vfx).Quality
local Util = require(script.Parent.Util)

local Pool = {}

local FAR = CFrame.new(0, -10000, 0)

local hub: Part? = nil
local atts: { Attachment } = {}
local beams: { Beam } = {}
local parts: { [Enum.PartType]: { Part } } = {}
local lights: { PointLight } = {}
local emitters: { ParticleEmitter } = {}
local litCount = 0

local function getHub(): Part
	local h = hub
	if h and h.Parent then
		return h
	end
	-- the folder was cleared: start the pools afresh
	atts, beams, parts, lights, emitters, litCount = {}, {}, {}, {}, {}, 0
	local made = Util.part(Vector3.one * 0.1, CFrame.identity)
	made.Name = "Hub"
	made.Parent = Util.folder()
	hub = made
	return made
end

local function keep<T>(list: { T }, item: T, destroy: () -> ())
	if #list < Q.MaxFree then
		table.insert(list, item)
	else
		destroy()
	end
end

function Pool.att(pos: Vector3): Attachment
	local h = getHub()
	local a = table.remove(atts)
	if not a or a.Parent ~= h then
		a = Instance.new("Attachment")
		assert(a, "attachment")
		a.Parent = h
	end
	a.CFrame = CFrame.new(pos)
	return a
end

function Pool.freeAtt(a: Attachment)
	keep(atts, a, function()
		a:Destroy()
	end)
end

-- A glowing camera-facing beam (no texture: a solid ribbon) between two attachments.
function Pool.beam(
	a0: Attachment,
	a1: Attachment,
	color: Color3,
	width0: number,
	width1: number,
	transparency: number,
	brightness: number,
	emission: number?
): Beam
	local h = getHub()
	local b = table.remove(beams)
	if not b or b.Parent ~= h then
		local made = Instance.new("Beam")
		made.LightEmission = 1
		made.LightInfluence = 0
		made.FaceCamera = true
		made.Parent = h
		b = made
	end
	assert(b, "beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.Color = ColorSequence.new(color)
	b.Width0, b.Width1 = width0, width1
	b.Transparency = NumberSequence.new(transparency)
	b.Brightness = brightness
	b.LightEmission = emission or 1
	b.CurveSize0, b.CurveSize1 = 0, 0
	b.Segments = 1
	b.ZOffset = 0
	b.Enabled = true
	return b
end

function Pool.freeBeam(b: Beam)
	b.Enabled = false
	b.Attachment0, b.Attachment1 = nil, nil
	keep(beams, b, function()
		b:Destroy()
	end)
end

-- A glowing (Neon) part, or one of `material` (debris).
function Pool.part(
	shape: Enum.PartType,
	color: Color3,
	size: Vector3,
	cf: CFrame,
	transparency: number?,
	material: Enum.Material?
): Part
	local list = parts[shape]
	if not list then
		list = {}
		parts[shape] = list
	end
	local h = getHub()
	local p = table.remove(list)
	if not p or p.Parent ~= h then
		p = Util.part(size, cf, color, shape)
		assert(p, "part")
		p.Parent = h
	end
	p.Color = color
	p.Size = size
	p.CFrame = cf
	p.Transparency = transparency or 0
	p.Material = material or Enum.Material.Neon
	return p
end

function Pool.freePart(p: Part)
	p.CFrame = FAR
	p.Transparency = 1
	local list = parts[p.Shape]
	if not list then
		list = {}
		parts[p.Shape] = list
	end
	keep(list, p, function()
		p:Destroy()
	end)
end

-- A point light at `pos`, or nil when Quality.MaxLights are already lit.
function Pool.light(pos: Vector3, color: Color3, range: number, brightness: number): PointLight?
	if litCount >= Q.MaxLights then
		return nil
	end
	litCount += 1
	local h = getHub()
	local l = table.remove(lights)
	if not l or not l.Parent or l.Parent.Parent ~= h then
		local made = Instance.new("PointLight")
		made.Shadows = false
		made.Parent = Pool.att(pos)
		l = made
	end
	assert(l, "light")
	local a = l.Parent :: Attachment
	a.CFrame = CFrame.new(pos)
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Enabled = true
	return l
end

function Pool.freeLight(l: PointLight)
	litCount = math.max(litCount - 1, 0)
	l.Enabled = false
	keep(lights, l, function()
		(l.Parent :: Instance):Destroy()
	end)
end

-- A particle emitter on its own invisible box part (the caller sets the emitter up; the part is the volume).
function Pool.emitter(cf: CFrame, size: Vector3): ParticleEmitter
	local e = table.remove(emitters)
	if not e or not e.Parent or e.Parent.Parent ~= getHub() then
		local p = Util.part(size, cf)
		p.Parent = getHub()
		local made = Instance.new("ParticleEmitter")
		made.Enabled = false
		made.LightInfluence = 0
		made.Parent = p
		e = made
	end
	assert(e, "emitter")
	local p = e.Parent :: Part
	p.Size = size
	p.CFrame = cf
	return e
end

function Pool.freeEmitter(e: ParticleEmitter)
	e.Enabled = false
	keep(emitters, e, function()
		(e.Parent :: Instance):Destroy()
	end)
end

return Pool
