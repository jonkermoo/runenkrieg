--!strict
-- Throwing a grenade on the local client (docs/MILESTONES.md G1; Config/Grenades, Rules/Grenade; the server throws it,
-- src/server/Grenades):
-- - with a grenade in the hands (Config/Weapons class "Grenade") and some left (the Tool's "Count"), holding the fire
--   key (Settings Key_Fire) shows a faint line from the throwing hand to where it would land (user: "Arc preview
--   line"); releasing throws it along the look (Net "GrenadeThrow"). Putting it away drops the arc unthrown.
-- - left click first pulls the pin (the "pin" one shot, "PinAt", Config/Grenades.Pin; the Mills's pin hidden once out,
--   "PinOut"); let go before it's out and the throw goes when it is. Another weapon drawn cancels it all.
-- - while the line shows the soldier holds the grenade drawn back (the "windup" hold, character attribute "Winding");
--   releasing plays the throw ("ThrownAt", src/client/Locomotion and src/client/Viewmodel) and the grenade is sent when
--   it leaves the hand, Config/Grenades.Throw.release into it, along the look at that moment.
-- - the arc is the throw's own path (Rules/Grenade.hand / launch / at, the same the server uses), drawn until the first
--   thing it would hit; the bounce and roll after that aren't drawn.
-- - every thrown grenade (Net "GrenadeFlight") moves along the path the server worked out (src/server/GrenadeFlight),
--   on the server's clock, its thunk (Config/Grenades.Thunk) at each hit loud enough to hear.
-- - every grenade that goes off (Net "GrenadeBlast") shows the shared explosion (src/client/Vfx/Blast) sized by its
--   charge, in Config/Grenades.Vfx's scheme, with its bang at its own pitch: heard late with distance and duller far off.

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

-- the thrown grenades in the air or rolling: each one's model put on its path every frame
type Flying = {
	model: Model,
	at: number,
	times: { number },
	frames: { CFrame },
	thunks: { { t: number, share: number, at: Vector3 } },
	pitch: number,
	seg: number,
	heard: number,
}
local flying: { Flying } = {}

local function thunk(f: Flying, share: number, at: Vector3)
	local T = Cfg.Thunk
	local e = table.clone(T.sounds[math.random(#T.sounds)] :: any)
	local lo, hi = T.pitchRange[1], T.pitchRange[2]
	e.pitch = f.pitch * (lo + (hi - lo) * math.random())
	SoundFx.play(e, at, nil, { volume = share })
end

local function fly()
	local now = workspace:GetServerTimeNow()
	for i = #flying, 1, -1 do
		local f = flying[i]
		local t = now - f.at
		if not f.model.Parent then
			table.remove(flying, i)
			continue
		end
		-- its thunks as it reaches them (one heard too late to match the hit is left out)
		while f.heard <= #f.thunks and f.thunks[f.heard].t <= t do
			local h = f.thunks[f.heard]
			if t - h.t <= Cfg.Thunk.late then
				thunk(f, h.share, h.at)
			end
			f.heard += 1
		end
		local times, frames = f.times, f.frames
		if t >= times[#times] then
			f.model:PivotTo(frames[#frames])
			if f.heard > #f.thunks then
				table.remove(flying, i)
			end
			continue
		end
		while f.seg < #times - 1 and times[f.seg + 1] <= t do
			f.seg += 1
		end
		local t0, t1 = times[f.seg], times[f.seg + 1]
		local k = if t1 > t0 then math.clamp((t - t0) / (t1 - t0), 0, 1) else 1
		f.model:PivotTo(frames[f.seg]:Lerp(frames[f.seg + 1], k))
	end
end

function Grenades.start()
	SoundFx.preload({ Bang = Cfg.Sound, Thunk = Cfg.Thunk.sounds })
	Net.event("GrenadeFlight").OnClientEvent
		:Connect(function(model: Model?, at: number, times: { number }, frames: { CFrame }, thunks: any, name: string)
			if typeof(model) ~= "Instance" or not (model :: Instance):IsA("Model") or #times < 1 then
				return
			end
			local t = Cfg.Types[name]
			table.insert(flying, {
				model = model :: Model,
				at = at,
				times = times,
				frames = frames,
				thunks = thunks,
				pitch = t and t.pitch or 1,
				seg = 1,
				heard = 1,
			})
		end)
	RunService.RenderStepped:Connect(fly)
	local player = Players.LocalPlayer
	local aiming = false -- left click held (or let go, waiting for the pin): the line shows
	local pinned = math.huge -- when the pin pull ends (os.clock)
	local wantThrow = false -- let go before the pin was out: throw the moment it is
	local releasing = false -- a throw on its way out of the hand

	-- the Mills's pin, hidden on the held grenade once pulled (the body here; src/client/Viewmodel its copy, "PinOut")
	-- (the part itself is kept: put back after another weapon was drawn, it's the grenade's, not the new weapon's)
	local pulled: BasePart? = nil
	local function pinOut(character: Model, out: boolean)
		if character:GetAttribute("PinOut") == (out or nil) then
			return
		end
		character:SetAttribute("PinOut", out or nil)
		if pulled then
			pulled.LocalTransparencyModifier = 0
			pulled = nil
		end
		local weapon = Held.weapon(character)
		local pin = weapon and weapon.tool:FindFirstChild("Pin", true)
		if out and pin and pin:IsA("BasePart") then
			pin.LocalTransparencyModifier = 1
			pulled = pin
		end
	end

	-- the pin pulled, drawn back and the line shown (`on`), or all of it dropped: thrown, put away, or another weapon
	-- drawn (cancelled: the pin pull stops, src/client/Locomotion)
	local function wind(on: boolean)
		aiming = on
		wantThrow = false
		local character = player.Character
		if character then
			character:SetAttribute("Winding", on)
			if on then
				local now = os.clock()
				pinned = now + Cfg.Pin.time
				character:SetAttribute("PinAt", now)
			end
		end
		if not on then
			pinned = math.huge
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
		local at = os.clock()
		character:SetAttribute("ThrownAt", at)
		-- the throw plays out even when the last one leaves the hand empty (src/client/WeaponCamera keeps the view)
		character:SetAttribute("Throwing", true)
		task.delay(Cfg.Throw.length, function()
			if character:GetAttribute("ThrownAt") == at then
				character:SetAttribute("Throwing", nil)
			end
		end)
		task.delay(Cfg.Throw.release, function()
			releasing = false
			if player.Character == character and grenade(character) then
				Net.event("GrenadeThrow"):FireServer(workspace.CurrentCamera.CFrame.LookVector)
				pinOut(character, false) -- the next one in the hand still has its pin
			elseif character:GetAttribute("ThrownAt") == at then
				-- another weapon drawn before it left the hand: no throw, the throw animation stops
				character:SetAttribute("ThrownAt", nil)
				character:SetAttribute("Throwing", nil)
				pinOut(character, false)
			end
		end)
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not Settings.pressed("Key_Fire", input) then
			return
		end
		if not aiming and not releasing and grenade(player.Character) then
			wind(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if not aiming or not Settings.pressed("Key_Fire", input) then
			return
		end
		if os.clock() >= pinned then
			throw()
		else
			wantThrow = true -- the pin isn't out yet
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
			wind(false) -- put away or another weapon drawn: no throw
			if character then
				pinOut(character, false)
			end
			return
		end
		local now = os.clock()
		if now >= pinned - Cfg.Pin.time + Cfg.Pin.out then
			pinOut(character, true)
		end
		if wantThrow and now >= pinned then
			throw()
			return
		end
		draw(character, head.Position, workspace.CurrentCamera.CFrame.LookVector, name)
	end)

	Net.event("GrenadeBlast").OnClientEvent:Connect(function(position: Vector3, kg: number, name: string)
		Vfx.Blast.play(position, { normal = Vector3.yAxis, kg = kg, scheme = Cfg.Vfx.scheme, magic = false })
		-- its bang at the grenade's own pitch, heard late and duller with distance (Rules/Grenade.heard)
		local t = Cfg.Types[name]
		local bang = {}
		for _, layer in Cfg.Sound do
			local e = table.clone(layer :: any)
			e.pitch = (e.pitch or 1) * (t and t.pitch or 1)
			table.insert(bang, e)
		end
		local d = (workspace.CurrentCamera.CFrame.Position - position).Magnitude
		local delay, high, low = Rules.heard(d, Cfg.Heard, AudioCfg.Heard.speed)
		SoundFx.play(bang :: any, position, nil, { delay = delay, eq = { low, 0, high } })
	end)
end

return Grenades
