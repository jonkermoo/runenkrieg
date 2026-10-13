--!strict
-- Shooting on the local client (M11; Config/Firing, Rules/Firing; the server decides in src/server/Firing):
-- - left click fires the held rifle; after a shot the next click works the bolt (by hand, user 2026-10-12); with
--   nothing to fire it clicks empty. R loads a clip into an empty magazine; with rounds left a stripper-clip rifle
--   loads single rounds until full, and a click stops it after the round in the hand (user 2026-10-13). No firing
--   while sprinting.
-- - the shot leaves the muzzle along the barrel, aimed or not (no cursor, no crosshair): aimed, that is the sights'
--   line, one sight height under it (Config/Weapons aiming contract).
-- - the client predicts its rifle's state with Rules/Firing and shows everything at once (GunFx: flash, sound,
--   tracer, hole, kick, bolt and clip motion; recoil through the sway layer); the server's state (Tool attributes)
--   is taken back once it has answered every request sent ("Seq").
-- - an empty rifle's bolt stays open (nothing happens on the trigger) until a clip goes in; put away mid-action, the
--   action plays out after the next draw (Config/Firing.Resume) and nothing fires until it's done.
-- - everyone else's shots and actions come from the server ("Shot", "WeaponAction") and play through GunFx.
-- - the ammo display (bottom right): the chambered round, then the magazine; a hint when the bolt or a clip is
--   needed. A hit note shows what the shot hit and how far (the range targets).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Firing)
local Palette = require(Shared.Config.Palette)
local W = require(Shared.Config.Weapons)
local F = require(Shared.Rules.Firing)
local Net = require(Shared.Net)
local GunFx = require(script.Parent.GunFx)
local Held = require(script.Parent.Held)
local Sway = require(script.Parent.Sway)

local Firing = {}

type Local = { state: F.State, gun: F.Gun, sent: number }
local states: { [Tool]: Local } = setmetatable({}, { __mode = "k" }) :: any

local function gunOf(name: string): F.Gun
	local w = W[name]
	return {
		capacity = w.ammo.capacity,
		clip = w.ammo.clip,
		boltTime = w.action.boltTime,
		reloadTime = w.action.reloadTime,
		fireTime = Cfg.FireTime,
		openAt = Cfg.BoltCycle.back,
		reloadOpenAt = Cfg.ReloadCycle.back,
		singleOpen = Cfg.Single.open,
		singleRound = Cfg.Single.round,
		singleClose = Cfg.Single.close,
	}
end

-- take the server's word: what the Tool attributes say
local function adopt(tool: Tool, l: Local)
	local m = tool:GetAttribute("Magazine")
	if type(m) == "number" then
		l.state.magazine = m
		l.state.chambered = tool:GetAttribute("Chambered") == true
		l.state.spent = tool:GetAttribute("Spent") == true
		l.state.open = tool:GetAttribute("Open") == true
		l.state.load = nil -- the server's numbers include any single rounds already in
	end
end

local function localState(tool: Tool, name: string): Local
	local l = states[tool]
	if not l then
		local gun = gunOf(name)
		l = { state = F.new(gun), gun = gun, sent = 0 }
		adopt(tool, l)
		states[tool] = l
		-- once the server has answered every request and nothing is moving, its state is the truth
		tool.AttributeChanged:Connect(function(attr)
			local seq = tool:GetAttribute("Seq")
			if (attr == "Seq" or attr == "Magazine") and (seq or 0) >= l.sent and os.clock() >= l.state.busyUntil then
				adopt(tool, l)
			end
		end)
		-- put away mid-action: it stops where it is; drawn again, the rest plays after the draw (as the server does)
		local holder = tool.Parent
		tool:GetPropertyChangedSignal("Parent"):Connect(function()
			local parent = tool.Parent
			local now = os.clock()
			if parent and parent:IsA("Backpack") then
				F.pause(l.state, now)
			elseif parent and parent:FindFirstChildOfClass("Humanoid") and parent ~= holder then
				F.resume(l.state, now, Cfg.Resume.delay)
				local character = parent :: Model
				task.delay(Cfg.Resume.delay, function()
					local c = GunFx.takeCut(tool)
					if c and tool.Parent == character then
						if c.action == "Load" then
							GunFx.load(character, c.weapon, c.out, c.from, c.to, c.magazine)
						else
							GunFx.cycle(character, c.weapon, c.action, c.out, c.magazine, c.from, c.to)
						end
					end
				end)
			end
			holder = parent
		end)
	end
	return l :: Local
end

local function bind(names: { string }): { [any]: boolean }
	local set = {}
	for _, k in names do
		local ok, key = pcall(function()
			return (Enum.KeyCode :: any)[k]
		end)
		set[if ok then key else (Enum.UserInputType :: any)[k]] = true
	end
	return set
end

local function excluded(character: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = { character, workspace.CurrentCamera }
	local fx = workspace:FindFirstChild("GunFx")
	if fx then
		table.insert(list, fx)
	end
	params.FilterDescendantsInstances = list
	return params
end

-- Where the shot starts and which way it goes: out of the visible gun's muzzle along its barrel (gun -Z), aimed or
-- not (user 2026-10-12: the bullet follows the barrel, never a cursor).
local function shotRay(character: Model): (Vector3?, Vector3?)
	local gun = GunFx.visible(character)
	local muzzle = gun and gun:FindFirstChild("Muzzle") :: Attachment?
	if not muzzle then
		return nil, nil
	end
	return muzzle.WorldPosition, muzzle.WorldCFrame.LookVector
end

-- ---- the ammo display and the hit note ----
type Hud = { gui: ScreenGui, chamber: Frame, slots: { Frame }, hint: TextLabel, note: TextLabel, noteUntil: number }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function round(parent: Instance, order: number): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(9, 30)
	f.BorderSizePixel = 0
	f.LayoutOrder = order
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Color = rgb(Palette.UI.outline)
	stroke.Thickness = 1.5
	stroke.Parent = f
	f.Parent = parent
	return f
end

local function buildHud(player: Player): Hud
	local gui = Instance.new("ScreenGui")
	gui.Name = "AmmoHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	local box = Instance.new("Frame")
	box.AnchorPoint = Vector2.new(1, 1)
	box.Position = UDim2.new(1, -24, 1, -24)
	box.Size = UDim2.fromOffset(0, 30)
	box.AutomaticSize = Enum.AutomaticSize.X
	box.BackgroundTransparency = 1
	box.Parent = gui
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = box
	local chamber = round(box, 0)
	local gap = Instance.new("Frame")
	gap.Size = UDim2.fromOffset(6, 1)
	gap.BackgroundTransparency = 1
	gap.LayoutOrder = 1
	gap.Parent = box
	local function label(y: number, size: number): TextLabel
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBold
		t.TextSize = size
		t.TextColor3 = rgb(Palette.UI.text)
		t.TextStrokeTransparency = 0.5
		t.Text = ""
		t.Parent = gui
		t.Position = UDim2.new(1, -24, 1, y)
		t.AnchorPoint = Vector2.new(1, 1)
		t.Size = UDim2.fromOffset(300, size + 4)
		t.TextXAlignment = Enum.TextXAlignment.Right
		return t
	end
	local hint = label(-60, 14)
	local note = label(0, 16)
	note.AnchorPoint = Vector2.new(0.5, 0.5)
	note.Position = UDim2.new(0.5, 0, 0.5, -40)
	note.TextXAlignment = Enum.TextXAlignment.Center
	gui.Parent = player:WaitForChild("PlayerGui")
	return { gui = gui, chamber = chamber, slots = {}, hint = hint, note = note, noteUntil = 0 }
end

local function slot(f: Frame, kind: string)
	f.BackgroundTransparency = if kind == "empty" then 0.5 else 0
	f.BackgroundColor3 =
		rgb(if kind == "round" then Palette.UI.round elseif kind == "spent" then Palette.UI.spent else Palette.UI.slot)
end

local function showHud(hud: Hud, l: Local?, now: number)
	hud.gui.Enabled = l ~= nil
	if not l then
		return
	end
	local s = l.state
	local box = hud.chamber.Parent :: Frame
	while #hud.slots < l.gun.capacity do
		table.insert(hud.slots, round(box, 2 + #hud.slots))
	end
	local magazine = F.magazineAt(s, now) -- single rounds already pushed in count
	for i, f in hud.slots do
		f.Visible = i <= l.gun.capacity
		slot(f, if i <= magazine then "round" else "empty")
	end
	slot(hud.chamber, if s.chambered then "round" elseif s.spent then "spent" else "empty")
	local next = F.next(s, now)
	hud.hint.Text = if next == "Load"
		then "Click: stop loading"
		elseif next == "Bolt" then "Click: work the bolt"
		elseif next == "Dry" or next == "Open" or (s.magazine == 0 and not s.chambered) then "R: load a clip"
		else ""
	hud.note.Visible = now < hud.noteUntil
end

function Firing.start()
	local player = Players.LocalPlayer
	local fireKeys, reloadKeys = bind(Cfg.Keys.Fire), bind(Cfg.Keys.Reload)
	GunFx.preload()
	local hud = buildHud(player)

	local function held(): (Model?, Held.Weapon?, Local?)
		local character = player.Character
		local weapon = character and Held.weapon(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not weapon or not humanoid or humanoid.Health <= 0 or not W[weapon.name] then
			return nil, nil, nil
		end
		return character, weapon, localState(weapon.tool, weapon.name)
	end

	local function fire()
		local character, weapon, l = held()
		if not character or not weapon or not l or character:GetAttribute("Sprinting") == true then
			return
		end
		local now = os.clock()
		local next = F.next(l.state, now)
		if next == "Load" then
			-- loading single rounds: stop after the round in the hand, then the bolt closes
			local k = F.stopLoad(l.state, now)
			if k then
				l.sent += 1
				Net.event("StopLoad"):FireServer()
				GunFx.loadStop(character, k)
			end
			return
		elseif next == "Fire" then
			local origin, dir = shotRay(character)
			if not origin or not dir then
				return
			end
			F.fire(l.state, l.gun, now)
			l.sent += 1
			Net.event("Fire"):FireServer(origin, dir)
			local result = workspace:Raycast(origin, dir * Cfg.Range, excluded(character))
			GunFx.shot(
				character,
				if result then result.Position else origin + dir * Cfg.Range,
				result and result.Normal,
				result and result.Instance
			)
			Sway.kick()
		elseif next == "Bolt" then
			local _, _, out = F.bolt(l.state, l.gun, now)
			l.sent += 1
			Net.event("WorkBolt"):FireServer()
			-- with nothing left to feed, the bolt stops pulled back (held open)
			local to = if l.state.open then Cfg.BoltCycle.back else 1
			GunFx.cycle(character, weapon.name, "Bolt", out, l.state.magazine, 0, to)
		elseif next == "Dry" then
			local gun = GunFx.visible(character)
			if gun then
				GunFx.sound(gun, "Dry")
			end
		end
	end

	local function reload()
		local character, weapon, l = held()
		if not character or not weapon or not l then
			return
		end
		local wasOpen = l.state.open
		local ok, _, out, kind = F.reload(l.state, l.gun, os.clock())
		if ok then
			l.sent += 1
			Net.event("Reload"):FireServer()
			local load = l.state.load
			if kind == "Load" and load then
				GunFx.load(character, weapon.name, out, 0, nil, load.room) -- single rounds
			else
				-- from an open bolt the clip goes straight in
				local from = if wasOpen then Cfg.ReloadCycle.back else 0
				GunFx.cycle(character, weapon.name, "Reload", out, l.state.magazine, from, 1)
			end
		end
	end

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if fireKeys[input.UserInputType] or fireKeys[input.KeyCode] then
			fire()
		elseif reloadKeys[input.KeyCode] then
			reload()
		end
	end)

	-- the server's shots and actions: everyone else's effects; for our own shots, the hit note
	Net.event("Shot").OnClientEvent
		:Connect(
			function(shooter: Model, _weapon: string, origin: Vector3, hit: Vector3, normal: Vector3?, part: Instance?)
				if typeof(shooter) ~= "Instance" then
					return
				end
				if shooter == player.Character then
					if
						part
						and (GunFx.isTarget(part) or part.Parent and part.Parent:FindFirstChildOfClass("Humanoid"))
					then
						local what = if GunFx.isTarget(part)
							then `{(part.Parent :: Instance).Name} {part.Name}`
							else part.Name
						hud.note.Text = `{what}  ·  {math.floor((hit - origin).Magnitude + 0.5)} studs`
						hud.noteUntil = os.clock() + Cfg.Effects.HitMarker.time
					end
					return
				end
				GunFx.shot(shooter, hit, normal, part)
			end
		)
	Net.event("WeaponAction").OnClientEvent
		:Connect(function(shooter: Model, action: string, out: string?, from: number?, to: number?, delay: number?)
			if typeof(shooter) ~= "Instance" or shooter == player.Character then
				return
			end
			local function play()
				local tool = shooter:FindFirstChildOfClass("Tool")
				local name = tool and tool:GetAttribute("Weapon")
				if not tool or type(name) ~= "string" or not W[name] then
					return
				end
				local magazine = tool:GetAttribute("Magazine")
				local m = if type(magazine) == "number" then magazine else 0
				if action == "Load" then
					GunFx.load(shooter, name, out, from or 0, to, W[name].ammo.capacity - m)
				elseif action == "LoadStop" then
					GunFx.loadStop(shooter, to or 0)
				else
					GunFx.cycle(shooter, name, action, out, m, from, to)
				end
			end
			if delay then
				task.delay(delay, play) -- drawn again: the rest of the cut action after the draw
			else
				play()
			end
		end)

	RunService.RenderStepped:Connect(function()
		local _, _, l = held()
		showHud(hud, l, os.clock())
	end)
end

return Firing
