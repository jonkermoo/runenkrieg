--!strict
-- The effects showcase (Config/Vfx.Showcase; user 2026-10-13: "show me some of the ones you were thinking
-- (labeled)"). DEV place only, on this client (the effects are client side): a floor off the map with a labeled pad
-- per effect, each playing on a loop while the player is near, aimed away from the viewer (-z). The beams and the
-- Zoltraak fire down a lane at a target block. Teleport "Effects showcase" (Config/DevTools).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Vfx).Showcase
local Spells = require(ReplicatedStorage:WaitForChild("Shared").Config.Spells)
local Grenades = require(ReplicatedStorage:WaitForChild("Shared").Config.Grenades)
local Artillery = require(ReplicatedStorage:WaitForChild("Shared").Config.Artillery)
local Vfx = require(script.Parent.Vfx)

local VfxShowcase = {}

local HEIGHT = 4.5 -- the effects play at about a staff tip's height
local LANE = 60 -- how far down the lane the targets stand (-z)
local FORWARD = Vector3.new(0, 0, -1)
local HOLDS = (function() -- each staff stage's hold time (Config/Spells), the tap held a moment
	local t = {}
	for i, s in Spells.Stages do
		t[i] = if i == 1 then 0.1 else s.hold
	end
	return t
end)()

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function block(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function label(parent: BasePart, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(240, 24)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.MaxDistance = 60
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextSize = 16
	t.TextColor3 = rgb(Cfg.Label)
	t.TextStrokeTransparency = 0.4
	t.Text = text
	t.Parent = gui
	gui.Parent = parent
end

-- a grey R6 stand-in for the aura to crackle round
local function dummy(parent: Instance, at: Vector3): Part
	local grey = Color3.fromRGB(163, 162, 165)
	local torso = block(parent, "Torso", Vector3.new(2, 2, 1), CFrame.new(at + Vector3.new(0, 3, 0)), grey)
	block(parent, "Head", Vector3.new(1.2, 1.2, 1.2), CFrame.new(at + Vector3.new(0, 4.6, 0)), grey)
	for _, x in { -1.5, 1.5 } do
		block(parent, "Arm", Vector3.new(1, 2, 1), CFrame.new(at + Vector3.new(x, 3, 0)), grey)
	end
	for _, x in { -0.5, 0.5 } do
		block(parent, "Leg", Vector3.new(1, 2, 1), CFrame.new(at + Vector3.new(x, 1, 0)), grey)
	end
	return torso
end

type Entry = { effect: string, label: string, every: number, scheme: string?, gun: string? }

local plays: { [string]: (pad: Vector3, folder: Folder, entry: Entry) -> () } = {
	Circle = function(p)
		Vfx.Circle.play(CFrame.lookAt(p, p + FORWARD), 1.2)
	end,
	Charge = function(p)
		Vfx.Charge.play(p)
	end,
	Ray = function(p, folder, entry)
		local to, normal, color = Vfx.Util.cast(p, FORWARD, LANE + 10, { folder:FindFirstChild("Pads") :: Instance })
		Vfx.Ray.play(p, to, { scheme = entry.scheme, normal = normal, hitColor = color })
	end,
	Burst = function(p, folder)
		local floor = folder:FindFirstChild("Floor") :: BasePart
		Vfx.Burst.play(Vector3.new(p.X, 0, p.Z), { normal = Vector3.yAxis, debrisColor = floor.Color })
	end,
	Blast1 = function(p, folder)
		local floor = folder:FindFirstChild("Floor") :: BasePart
		Vfx.Blast.play(Vector3.new(p.X, 0, p.Z), { normal = Vector3.yAxis, debrisColor = floor.Color, stage = 1 })
	end,
	Blast3 = function(p, folder)
		local floor = folder:FindFirstChild("Floor") :: BasePart
		Vfx.Blast.play(Vector3.new(p.X, 0, p.Z), { normal = Vector3.yAxis, debrisColor = floor.Color, stage = 3 })
	end,
	-- the grenade, the field gun's shell and the howitzer's, as in play (Config/Grenades, Config/Artillery)
	Grenade = function(p)
		local G = Grenades.Vfx
		local kg = (Grenades.Types :: any)[Cfg.Grenade].kg
		Vfx.Blast.play(Vector3.new(p.X, 0, p.Z), { normal = Vector3.yAxis, kg = kg, scheme = G.scheme, pop = G.pop })
	end,
	Shell = function(p, _, entry)
		local gun = (Artillery.Guns :: any)[entry.gun]
		Vfx.Blast.play(
			Vector3.new(p.X, 0, p.Z),
			{ normal = Vector3.yAxis, kg = gun.kg, scheme = gun.vfx.scheme, magic = gun.vfx.magic }
		)
	end,
	Shockwave = function(p)
		Vfx.Shockwave.play(Vector3.new(p.X, 0.3, p.Z), Vector3.yAxis)
	end,
	Star = function(p)
		Vfx.Star.play(p)
	end,
	Spikes = function(p)
		Vfx.Spikes.play(p)
	end,
	Lightning = function(p)
		Vfx.Lightning.bolt(p + Vector3.new(-2, 7, -3), Vector3.new(p.X + 1, 0, p.Z - 3))
	end,
	Aura = function(p, folder, entry)
		local torso = folder:FindFirstChild("AuraDummy") :: Part?
		if not torso then
			local m = Instance.new("Model")
			m.Name = "Dummy"
			m.Parent = folder
			torso = dummy(m, Vector3.new(p.X, 0, p.Z - 4))
			assert(torso, "the aura dummy has a torso")
			torso.Name = "AuraDummy"
			torso.Parent = folder
		end
		Vfx.Aura.play(torso :: Part, entry.every * 0.8)
	end,
	Cast1 = function(p, folder, entry)
		Vfx.Zoltraak.cast(
			CFrame.lookAt(p, p + FORWARD),
			1,
			HOLDS,
			{ folder:FindFirstChild("Pads") :: Instance },
			entry.scheme
		)
	end,
	Cast2 = function(p, folder, entry)
		Vfx.Zoltraak.cast(
			CFrame.lookAt(p, p + FORWARD),
			2,
			HOLDS,
			{ folder:FindFirstChild("Pads") :: Instance },
			entry.scheme
		)
	end,
	Cast3 = function(p, folder, entry)
		Vfx.Zoltraak.cast(
			CFrame.lookAt(p, p + FORWARD),
			3,
			HOLDS,
			{ folder:FindFirstChild("Pads") :: Instance },
			entry.scheme
		)
	end,
	Zoltraak = function(p, folder, entry)
		Vfx.Zoltraak.play(CFrame.lookAt(p, p + FORWARD), { folder:FindFirstChild("Pads") :: Instance }, entry.scheme)
	end,
}

function VfxShowcase.start()
	if game.PlaceId ~= Cfg.PlaceId then
		return
	end
	local old = workspace:FindFirstChild("DevVfx")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "DevVfx"
	local o = Vector3.new(Cfg.Origin[1], Cfg.Origin[2], Cfg.Origin[3])
	local n = #Cfg.Entries
	local width = (n - 1) * Cfg.Spacing + 30
	local floorColor = rgb(Cfg.Floor)
	block(
		folder,
		"Floor",
		Vector3.new(width, 1, LANE + 40),
		CFrame.new(o + Vector3.new((n - 1) * Cfg.Spacing / 2, -0.5, -LANE / 2 + 10)),
		floorColor
	)
	local pads = Instance.new("Folder")
	pads.Name = "Pads"
	pads.Parent = folder
	for i, entry in Cfg.Entries do
		local x = o + Vector3.new((i - 1) * Cfg.Spacing, 0, 0)
		local pad = block(
			pads,
			entry.effect,
			Vector3.new(4, 0.2, 4),
			CFrame.new(x + Vector3.new(0, 0.1, 6)),
			floorColor:Lerp(Color3.new(), 0.3)
		)
		label(pad, `{i}. {entry.label}`)
		-- a target block down the lane for the beams
		if entry.effect == "Ray" or entry.effect == "Zoltraak" or string.sub(entry.effect, 1, 4) == "Cast" then
			block(folder, "Target", Vector3.new(6, 8, 2), CFrame.new(x + Vector3.new(0, 4, -LANE + 1)), rgb(Cfg.Target))
		end
		local play = plays[entry.effect]
		assert(play, "no showcase play for " .. entry.effect)
		task.spawn(function()
			task.wait(i * 0.2)
			while folder.Parent do
				local char = Players.LocalPlayer.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and (root.Position - x).Magnitude < Cfg.Range then
					play(x + Vector3.new(0, HEIGHT, 0), folder, entry :: Entry)
				end
				task.wait(entry.every)
			end
		end)
	end
	folder.Parent = workspace
end

return VfxShowcase
