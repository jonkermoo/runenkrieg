--!strict
-- Throwing a grenade on the local client (docs/MILESTONES.md G1; Config/Grenades, Rules/Grenade; the server throws it,
-- src/server/Grenades):
-- - with a grenade in the hands (Config/Weapons class "Grenade") and some left (the Tool's "Count"), holding the fire
--   key (Settings Key_Fire) shows a faint line from the throwing hand to where it would land (user: "Arc preview
--   line"); releasing throws it along the look (Net "GrenadeThrow"). Putting it away drops the arc unthrown.
-- - while the line shows the soldier holds the grenade drawn back (the "windup" hold, character attribute "Winding");
--   releasing plays the throw ("ThrownAt", src/client/Locomotion and src/client/Viewmodel) and the grenade is sent when
--   it leaves the hand, Config/Grenades.Throw.release into it, along the look at that moment.
-- - on touch screens a round throw button does the same (Config/Grenades.Touch): hold for the line, lift to throw,
--   slide off it and lift to put the throw back.
-- - the arc is the throw's own path (Rules/Grenade.hand / launch / at, the same the server uses), drawn until the first
--   thing it would hit; the bounce and roll after that aren't drawn.
-- - every grenade that goes off (Net "GrenadeBlast") shows the shared explosion (src/client/Vfx/Blast) sized by its
--   charge, in Config/Grenades.Vfx's scheme, with its bang: heard late with distance and duller far off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioCfg = require(Shared.Config.Audio)
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

-- the line: one Beam between two attachments on the terrain (client only), bent to the throw's own parabola (a
-- parabola is a Bezier curve: its control points sit a third of the flight along the velocity at each end)
local beam: Beam? = nil
local a0: Attachment? = nil
local a1: Attachment? = nil

local function line(): (Beam, Attachment, Attachment)
	if not beam or not beam.Parent or not a0 or not a1 then
		local c = Palette.Grenades.Arc
		a0 = Instance.new("Attachment")
		a1 = Instance.new("Attachment")
		local b = Instance.new("Beam")
		b.Name = "GrenadeArc"
		b.Attachment0, b.Attachment1 = a0, a1
		b.FaceCamera = true
		b.Segments = A.segments
		b.Width0, b.Width1 = A.width, A.width
		b.Color = ColorSequence.new(Color3.fromRGB(c[1], c[2], c[3]))
		b.Transparency = NumberSequence.new(A.transparency)
		b.LightEmission = 0
		b.Enabled = false
		(a0 :: Attachment).Parent = workspace.Terrain;
		(a1 :: Attachment).Parent = workspace.Terrain
		b.Parent = workspace.Terrain
		beam = b
	end
	return beam :: Beam, a0 :: Attachment, a1 :: Attachment
end

local function hide()
	if beam then
		beam.Enabled = false
	end
end

-- an attachment at `at` whose X axis points along `axis`
local function along(a: Attachment, at: Vector3, axis: Vector3)
	local x = if axis.Magnitude > 1e-6 then axis.Unit else Vector3.xAxis
	local y = x:Cross(Vector3.yAxis)
	y = if y.Magnitude > 1e-3 then y.Unit else Vector3.zAxis
	a.WorldCFrame = CFrame.fromMatrix(at, x, y)
end

-- draws the line for a throw along `look` from `head`: from where it is `near` studs from the eye to the first thing
-- it would hit (or `time` seconds)
local function draw(character: Model, head: Vector3, look: Vector3, name: string)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, workspace.CurrentCamera }
	params.IgnoreWater = false
	-- the hand, never past a wall between it and the head (as src/server/Grenades.hand)
	local hx, hy, hz = Rules.hand(head.X, head.Y, head.Z, look.X, look.Y, look.Z, Cfg.Throw.from)
	local reach = Vector3.new(hx, hy, hz) - head
	local block = workspace:Raycast(head, reach, params)
	local start = head + reach * Rules.clearShare(reach.Magnitude, block and block.Distance, Cfg.Throw.gap)
	local ox, oy, oz = start.X, start.Y, start.Z
	local vx, vy, vz = Rules.launch(look.X, look.Y, look.Z, Cfg.Throw.loft, Cfg.Types[name].speed)
	local g = workspace.Gravity
	local eye = workspace.CurrentCamera.CFrame.Position
	local function at(t: number): Vector3
		local x, y, z = Rules.at(t, ox, oy, oz, vx, vy, vz, g)
		return Vector3.new(x, y, z)
	end
	local dt = A.spacing / math.max(Vector3.new(vx, vy, vz).Magnitude, 1)
	local first: number? = nil -- the first time it's `near` from the eye
	local last, finish = 0, nil :: Vector3?
	local prev = at(0)
	local t = dt
	while t <= A.time do
		local p = at(t)
		local hit = workspace:Raycast(prev, p - prev, params)
		if hit then
			last = t - dt + dt * hit.Distance / (p - prev).Magnitude
			finish = hit.Position
			break
		end
		if not first and (p - eye).Magnitude >= A.near then
			first = t
		end
		last = t
		prev = p
		t += dt
	end
	local t0 = first or 0
	if last <= t0 then
		hide()
		return
	end
	local b, s0, s1 = line()
	local p0, p1 = at(t0), finish or at(last)
	local v0 = Vector3.new(vx, vy - g * t0, vz)
	local v1 = Vector3.new(vx, vy - g * last, vz)
	local third = (last - t0) / 3
	along(s0, p0, v0)
	along(s1, p1, v1)
	b.CurveSize0 = v0.Magnitude * third
	b.CurveSize1 = v1.Magnitude * third
	b.Enabled = true
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- the touch throw button (Config/Grenades.Touch), hidden until a grenade is out
local function button(player: Player): (ScreenGui, TextButton)
	local T, UI = Cfg.Touch, Palette.UI
	local gui = Instance.new("ScreenGui")
	gui.Name = "GrenadeThrow"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local b = Instance.new("TextButton")
	b.Name = "Throw"
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, -T.right, 1, -T.bottom)
	b.Size = UDim2.fromOffset(T.size, T.size)
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.BackgroundColor3 = rgb(UI.button)
	b.BackgroundTransparency = T.idle
	b.Font = Enum.Font.GothamBold
	b.Text = "THROW"
	b.TextSize = T.text
	b.TextColor3 = rgb(UI.text)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = b
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Thickness = UI.stroke
	edge.Color = rgb(UI.outline)
	edge.Parent = b
	b.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui, b
end

-- is the screen point `at` on the round button?
local function onButton(b: GuiObject, at: Vector3): boolean
	local centre = b.AbsolutePosition + b.AbsoluteSize / 2
	return (Vector2.new(at.X, at.Y) - centre).Magnitude <= b.AbsoluteSize.X / 2
end

function Grenades.start()
	local player = Players.LocalPlayer
	local aiming = false
	local releasing = false -- a throw on its way out of the hand

	local function wind(on: boolean)
		aiming = on
		local character = player.Character
		if character then
			character:SetAttribute("Winding", on)
		end
		if not on then
			hide()
		end
	end

	local function throw()
		wind(false)
		local character = player.Character
		if releasing or not character or not grenade(character) then
			return
		end
		releasing = true
		character:SetAttribute("ThrownAt", os.clock())
		task.delay(Cfg.Throw.release, function()
			releasing = false
			if player.Character == character and grenade(character) then
				Net.event("GrenadeThrow"):FireServer(workspace.CurrentCamera.CFrame.LookVector)
			end
		end)
	end

	-- touch: the button's own touch, followed until it lifts
	local touchGui, touchButton = button(player)
	local finger: InputObject? = nil
	touchButton.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.Touch
			and not finger
			and not releasing
			and grenade(player.Character)
		then
			finger = input
			wind(true)
			touchButton.BackgroundTransparency = Cfg.Touch.press
		end
	end)
	UserInputService.TouchEnded:Connect(function(input)
		if input ~= finger then
			return
		end
		finger = nil
		touchButton.BackgroundTransparency = Cfg.Touch.idle
		if not aiming then
			return
		end
		-- (a touch's Position and the button's AbsolutePosition are both below the top bar inset)
		if onButton(touchButton, input.Position) then
			throw()
		else
			wind(false) -- slid off: put back
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not Settings.pressed("Key_Fire", input) then
			return
		end
		if not releasing and grenade(player.Character) then
			wind(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not aiming or finger or not Settings.pressed("Key_Fire", input) then
			return
		end
		throw()
	end)
	RunService.RenderStepped:Connect(function()
		touchGui.Enabled = UserInputService.TouchEnabled and grenade(player.Character) ~= nil
		if not aiming then
			return
		end
		local character = player.Character
		local _, name = grenade(character)
		local head = character and character:FindFirstChild("Head") :: BasePart?
		if not character or not name or not head then
			wind(false) -- put away or out: no throw
			return
		end
		draw(character, head.Position, workspace.CurrentCamera.CFrame.LookVector, name)
	end)

	Net.event("GrenadeBlast").OnClientEvent:Connect(function(position: Vector3, kg: number)
		Vfx.Blast.play(position, { normal = Vector3.yAxis, kg = kg, scheme = Cfg.Vfx.scheme, magic = false })
		-- heard late and duller with distance (Rules/Grenade.heard)
		local d = (workspace.CurrentCamera.CFrame.Position - position).Magnitude
		local delay, high, low = Rules.heard(d, Cfg.Heard, AudioCfg.Heard.speed)
		SoundFx.play(Cfg.Sound :: any, position, nil, { delay = delay, eq = { low, 0, high } })
	end)
end

return Grenades
