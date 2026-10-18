--!strict
-- Throwing a grenade on the local client (docs/MILESTONES.md G1; Config/Grenades, Rules/Grenade; the server throws it,
-- src/server/Grenades):
-- - with a grenade in the hands (Config/Weapons class "Grenade") and some left (the Tool's "Count"), holding the fire
--   key (Settings Key_Fire) shows a faint dotted arc from the throwing hand to where it would land (user: "Arc preview
--   line"); releasing throws it along the look (Net "GrenadeThrow"). Putting it away drops the arc unthrown.
-- - the arc is the throw's own path (Rules/Grenade.hand / launch / at, the same the server uses), drawn until the first
--   thing it would hit; the bounce and roll after that aren't drawn.
-- - every grenade that goes off (Net "GrenadeBlast") shows the shared explosion (src/client/Vfx/Blast) sized by its
--   charge, in Config/Grenades.Vfx's scheme, with its bang.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Grenades)
local Palette = require(Shared.Config.Palette)
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.Grenade)
local Net = require(Shared.Net)
local Held = require(script.Parent.Held)
local Settings = require(script.Parent.Settings)
local SoundFx = require(script.Parent.SoundFx)
local Vfx = require(script.Parent.Vfx)

local Grenades = {}

local A = Cfg.Arc

-- the held grenade with some left, or nil
local function grenade(character: Model?): (Held.Weapon?, string?)
	local weapon = Held.weapon(character)
	local name = weapon and weapon.name
	local count = weapon and weapon.tool:GetAttribute("Count")
	if weapon and name and W[name] and W[name].class == "Grenade" and Cfg.Types[name] then
		if type(count) == "number" and count > 0 then
			return weapon, name
		end
	end
	return nil, nil
end

-- the dots, pooled (client only, under the camera)
local dots: { Part } = {}
local folder: Folder? = nil

local function dot(i: number): Part
	local d = dots[i]
	if not d then
		if not folder or not folder.Parent then
			local f = Instance.new("Folder")
			f.Name = "GrenadeArc"
			f.Parent = workspace.CurrentCamera
			folder = f
		end
		local c = Palette.Grenades.Arc
		d = Instance.new("Part")
		d.Name = "Dot"
		d.Shape = Enum.PartType.Ball
		d.Anchored = true
		d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
		d.CastShadow = false
		d.Material = Enum.Material.SmoothPlastic
		d.Color = Color3.fromRGB(c[1], c[2], c[3])
		d.Transparency = A.transparency
		d.Parent = folder
		dots[i] = d
	end
	return d
end

local function hide(from: number)
	for i = from, #dots do
		dots[i].Transparency = 1
	end
end

-- draws the arc for a throw along `look` from `head`; the dots past the first hit stay hidden
local function draw(character: Model, head: Vector3, look: Vector3, name: string)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, workspace.CurrentCamera }
	params.IgnoreWater = false
	-- the hand, never past a wall between it and the head (as src/server/Grenades.hand)
	local hx, hy, hz = Rules.hand(head.X, head.Y, head.Z, look.X, look.Y, look.Z, Cfg.Throw.from)
	local line = Vector3.new(hx, hy, hz) - head
	local block = workspace:Raycast(head, line, params)
	local start = head + line * Rules.clearShare(line.Magnitude, block and block.Distance, Cfg.Throw.gap)
	local ox, oy, oz = start.X, start.Y, start.Z
	local vx, vy, vz = Rules.launch(look.X, look.Y, look.Z, Cfg.Throw.loft, Cfg.Types[name].speed)
	local g = workspace.Gravity
	local prev = Vector3.new(ox, oy, oz)
	local n = 0
	local t = A.step
	while t <= A.time do
		local x, y, z = Rules.at(t, ox, oy, oz, vx, vy, vz, g)
		local p = Vector3.new(x, y, z)
		local hit = workspace:Raycast(prev, p - prev, params)
		n += 1
		local d = dot(n)
		if hit then
			d.Size = Vector3.one * A.landSize
			d.Position = hit.Position
			d.Transparency = A.transparency
			break
		end
		d.Size = Vector3.one * A.size
		d.Position = p
		d.Transparency = A.transparency
		prev = p
		t += A.step
	end
	hide(n + 1)
end

function Grenades.start()
	local player = Players.LocalPlayer
	local aiming = false

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not Settings.pressed("Key_Fire", input) then
			return
		end
		if grenade(player.Character) then
			aiming = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not aiming or not Settings.pressed("Key_Fire", input) then
			return
		end
		aiming = false
		hide(1)
		if grenade(player.Character) then
			Net.event("GrenadeThrow"):FireServer(workspace.CurrentCamera.CFrame.LookVector)
		end
	end)
	RunService.RenderStepped:Connect(function()
		if not aiming then
			return
		end
		local character = player.Character
		local _, name = grenade(character)
		local head = character and character:FindFirstChild("Head") :: BasePart?
		if not character or not name or not head then
			aiming = false -- put away or out: no throw
			hide(1)
			return
		end
		draw(character, head.Position, workspace.CurrentCamera.CFrame.LookVector, name)
	end)

	Net.event("GrenadeBlast").OnClientEvent:Connect(function(position: Vector3, kg: number)
		Vfx.Blast.play(position, { normal = Vector3.yAxis, kg = kg, scheme = Cfg.Vfx.scheme, magic = false })
		SoundFx.play(Cfg.Sound :: any, position)
	end)
end

return Grenades
