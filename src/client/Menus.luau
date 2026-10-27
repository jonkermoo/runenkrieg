--!strict
-- The title screen and the loadout menu (user 2026-10-27), over the live match (src/client/MatchCam). There is no
-- character until the player deploys (src/server/Deploy): the title screen shows on join (Play, Customization still
-- locked, Settings), Play opens the loadout menu, and the loadout menu opens again Config/Classes.MenuAfterDeath
-- seconds after every death; its Back button returns to the title screen. The menu lists the classes (Config/Classes.List: name, blurb, cost; picked, locked or
-- not affordable), the match currency (shown only here, user: "they only see their match currency in the loadout menu
-- when they are respawning"), and the soldier you'll spawn as, turning slowly: the server's "LoadoutPreview" rig in a
-- ViewportFrame, playing its primary's ready hold. Deploy lights up once the respawn delay is over (Net "Loadout").
-- Layout, sizes and the one basic font come from src/shared/ui/TitleScreen.json and LoadoutMenu.json (the local
-- layout check and preview read the same files); offsets are reference pixels, scaled here by the GUI height. Colours:
-- Config/Palette UI.Settings. No CanvasGroup: every element sets its own transparency.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared.Config.Classes)
local Locomotion = require(Shared.Config.Locomotion)
local Palette = require(Shared.Config.Palette)
local U = require(Shared.Config.Uniforms)
local W = require(Shared.Config.Weapons)
local MovementSet = require(Shared.Rules.MovementSet)
local Net = require(Shared.Net)
local TitleSpec = require(Shared.ui.TitleScreen) :: any
local LoadoutSpec = require(Shared.ui.LoadoutMenu) :: any
local MatchCam = require(script.Parent.MatchCam)
local SettingsMenu = require(script.Parent.SettingsMenu)

local Menus = {}

local C = Palette.UI.Settings :: any
local Anims = MovementSet.animations(Locomotion) :: any
local DISPLAY_ORDER = 5 -- under the settings menu (Config/Settings.Menu.DisplayOrder)

local function rgb(name: string): Color3
	local c = C[name]
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function fontOf(spec: any): Font
	local f = spec.theme.fonts.body
	return Font.new(`rbxasset://fonts/families/{f.family}.json`, (Enum.FontWeight :: any)[f.weight])
end

local ALIGN = { left = Enum.TextXAlignment.Left, right = Enum.TextXAlignment.Right }

-- One screen built from its spec: every node by id, laid out again at the GUI's scale when the window changes.
type Screen = { gui: ScreenGui, node: { [string]: GuiObject }, spec: { [string]: any }, relayout: () -> () }

local function build(spec: any, name: string, parent: Instance): Screen
	local T = spec.theme
	local font = fontOf(spec)
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = DISPLAY_ORDER
	gui.Enabled = false
	local screen: Screen = { gui = gui, node = {}, spec = {}, relayout = function() end }
	local placed: { { obj: GuiObject, n: any } } = {}

	local function make(n: any, into: Instance)
		local obj: GuiObject
		if n.kind == "button" then
			local b = Instance.new("TextButton")
			b.AutoButtonColor = false
			obj = b
		elseif n.kind == "label" then
			obj = Instance.new("TextLabel")
		elseif n.kind == "model" then
			obj = Instance.new("ViewportFrame")
		elseif n.kind == "image" then
			local img = Instance.new("ImageLabel")
			img.ScaleType = Enum.ScaleType.Fit
			obj = img
		else
			obj = Instance.new("Frame")
		end
		obj.Name = n.id
		obj.BorderSizePixel = 0
		obj.BackgroundTransparency = 1
		if (n.kind == "panel" or n.kind == "button") and not n.clear then
			obj.BackgroundTransparency = 0
			obj.BackgroundColor3 = rgb(n.color or "field")
			local corner = Instance.new("UICorner")
			corner.Parent = obj
			if n.line then
				local stroke = Instance.new("UIStroke")
				stroke.Color = rgb(n.line)
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Parent = obj
			end
		end
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			obj.FontFace = font
			obj.Text = n.text or ""
			obj.TextColor3 = rgb(n.textColor or "text")
			obj.TextXAlignment = ALIGN[n.align] or Enum.TextXAlignment.Center
			obj.TextTruncate = Enum.TextTruncate.AtEnd
		end
		if obj:IsA("ViewportFrame") then
			obj.BackgroundTransparency = 1
		end
		if n.anchor then
			obj.AnchorPoint = Vector2.new(n.anchor[1], n.anchor[2])
		end
		screen.node[n.id] = obj
		screen.spec[n.id] = n
		table.insert(placed, { obj = obj, n = n })
		for _, c in n.children or {} do
			make(c, obj)
		end
		obj.Parent = into
	end
	make(spec.root, gui)

	function screen.relayout()
		local h = gui.AbsoluteSize.Y
		if h <= 0 then
			return
		end
		local s = math.clamp(h / T.scale.referenceHeight, T.scale.min, T.scale.max)
		for _, p in placed do
			local n, obj = p.n, p.obj
			local pos, size = n.pos or { 0, 0, 0, 0 }, n.size or { 1, 0, 1, 0 }
			obj.Position = UDim2.new(pos[1], pos[2] * s, pos[3], pos[4] * s)
			obj.Size = UDim2.new(size[1], size[2] * s, size[3], size[4] * s)
			if obj:IsA("TextLabel") or obj:IsA("TextButton") then
				obj.TextSize = (n.textSize or 20) * s
			end
			local corner = obj:FindFirstChildOfClass("UICorner")
			if corner then
				corner.CornerRadius = UDim.new(0, T.corner * s)
			end
			local stroke = obj:FindFirstChildOfClass("UIStroke")
			if stroke then
				-- the screen's own panel: the theme's stroke, else thin
				stroke.Thickness = if n.id == "Panel" then C.stroke else C.thin
			end
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(screen.relayout)
	gui.Parent = parent
	return screen
end

-- a box's look: fill, line and text colours
local function paint(obj: GuiObject, fill: string, line: string, textColor: string)
	obj.BackgroundColor3 = rgb(fill)
	local stroke = obj:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = rgb(line)
	end
	if obj:IsA("TextButton") or obj:IsA("TextLabel") then
		obj.TextColor3 = rgb(textColor)
	end
end

function Menus.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local title = build(TitleSpec, "TitleScreen", playerGui)
	local loadout = build(LoadoutSpec, "LoadoutMenu", playerGui)
	local L = loadout.node

	-- the class rows: the spec's first row is the template, one copy per class (the samples go)
	local list = L.List
	local template = L.RowRifleman
	local rowStep = (loadout.spec.RowGrenadier.pos[4] - loadout.spec.RowRifleman.pos[4]) :: number
	for _, c in list:GetChildren() do
		if c ~= template then
			c:Destroy()
		end
	end
	template.Parent = nil
	type Row = { button: TextButton, name: TextLabel, blurb: TextLabel, cost: TextLabel }
	local rows: { [string]: Row } = {}
	local order: { string } = {}
	for i, key in Classes.List do
		local b = template:Clone() :: TextButton
		b.Name = "Row" .. key
		b.LayoutOrder = i
		local name = b:FindFirstChild("RiflemanName") :: TextLabel
		local blurb = b:FindFirstChild("RiflemanBlurb") :: TextLabel
		local cost = b:FindFirstChild("RiflemanCost") :: TextLabel
		name.Text = Classes.Defs[key].name
		blurb.Text = Classes.Defs[key].blurb
		b.Parent = list
		rows[key] = { button = b, name = name, blurb = blurb, cost = cost }
		table.insert(order, key)
	end
	-- the copies follow the template's place, one step apart (scaled with the rest)
	local baseRelayout = loadout.relayout
	function loadout.relayout()
		baseRelayout()
		local base = template.Position
		for i, key in order do
			local b = rows[key].button
			local s = template.Size
			b.Size = s
			b.Position = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset)
				+ UDim2.fromOffset(0, (i - 1) * rowStep * (s.Y.Offset / loadout.spec.RowRifleman.size[4]))
			for _, part in { "name", "blurb", "cost" } do
				local cell = (rows[key] :: any)[part] :: TextLabel
				local t = template:FindFirstChild("Rifleman" .. part:sub(1, 1):upper() .. part:sub(2)) :: TextLabel
				cell.Position, cell.Size, cell.TextSize = t.Position, t.Size, t.TextSize
			end
		end
	end
	loadout.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(loadout.relayout)

	-- the soldier you'll spawn as
	local view = L.Model :: ViewportFrame
	local P = Classes.Preview
	view.Ambient = Color3.fromRGB(P.Ambient[1], P.Ambient[2], P.Ambient[3])
	view.LightColor = Color3.fromRGB(P.Light[1], P.Light[2], P.Light[3])
	view.LightDirection = Vector3.new(-1, -1, -1)
	local viewCam = Instance.new("Camera")
	viewCam.FieldOfView = P.Fov
	viewCam.Parent = view
	view.CurrentCamera = viewCam
	local world = Instance.new("WorldModel")
	world.Parent = view
	local shown: Model? = nil
	local function showPreview()
		if shown then
			shown:Destroy()
			shown = nil
		end
		local rig = playerGui:FindFirstChild("LoadoutPreview")
		if not rig or not rig:IsA("Model") then
			return
		end
		local m = rig:Clone()
		m.Parent = world
		shown = m
		local humanoid = m:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = humanoid
		local function play(id: number?, priority: Enum.AnimationPriority)
			if not id or id == 0 then
				return
			end
			local a = Instance.new("Animation")
			a.AnimationId = "rbxassetid://" .. id
			local t = (animator :: Animator):LoadAnimation(a)
			t.Priority = priority
			t.Looped = true
			t:Play(0)
		end
		play(Anims.idle and Anims.idle.id, Enum.AnimationPriority.Core)
		local primary = m:GetAttribute("Primary")
		local w = type(primary) == "string" and W[primary]
		if w then
			play(w.holds.ready, Enum.AnimationPriority.Action)
		end
	end
	playerGui.ChildAdded:Connect(function(c)
		if c.Name == "LoadoutPreview" then
			task.defer(showPreview)
		end
	end)

	local state: any = nil
	local deployAt = 0
	local function render()
		if not state then
			return
		end
		local marks = L.Marks :: TextLabel
		marks.Text = `{Classes.Currency}  {state.points}`
		local picked = state.picked
		for _, card in state.classes do
			local r = rows[card.key]
			if r then
				local can = not card.locked and card.affordable
				local on = card.key == picked
				local fill, line, main, sub = "field", "line", "text", "textDim"
				if on then
					fill, line, main, sub = "selFill", "selLine", "selText", "text"
				elseif not can then
					main = "textDim"
				end
				paint(r.button, fill, line, main)
				r.name.TextColor3, r.cost.TextColor3, r.blurb.TextColor3 = rgb(main), rgb(main), rgb(sub)
				r.cost.Text = if card.locked then "Soon" elseif card.cost == 0 then "Free" else tostring(card.cost)
			end
		end
		local def = Classes.Defs[picked]
		local className = L.ClassName :: TextLabel
		className.Text = if def then def.name else ""
	end

	local function setTeam(kit: any)
		local k = type(kit) == "string" and (U.Kits :: any)[kit]
		local team = title.node.Team :: TextLabel
		team.Text = if k and k.army then `For {k.army}` else ""
		local flag = title.node.Flag :: ImageLabel
		flag.Image = if k and k.flag then `rbxassetid://{k.flag.full}` else ""
	end

	local menuOpen = false
	local function refresh()
		menuOpen = title.gui.Enabled or loadout.gui.Enabled
		if menuOpen then
			MatchCam.start()
		else
			MatchCam.stop()
		end
	end
	local function open(which: Screen?)
		title.gui.Enabled = which == title
		loadout.gui.Enabled = which == loadout
		if which then
			which.relayout()
		end
		if which == loadout then
			loadout.relayout()
		end
		refresh()
	end

	for key, r in rows do
		r.button.Activated:Connect(function()
			local card = state
				and (function()
					for _, c in state.classes do
						if c.key == key then
							return c
						end
					end
					return nil
				end)()
			if card and not card.locked and card.affordable then
				Net.event("Loadout"):FireServer("Pick", key)
			end
		end)
	end
	local back = L.Back :: TextButton
	back.Activated:Connect(function()
		open(title)
	end)
	local deploy = L.Deploy :: TextButton
	deploy.Activated:Connect(function()
		if state and os.clock() >= deployAt then
			Net.event("Loadout"):FireServer("Deploy")
		end
	end)
	local play = title.node.Play :: TextButton
	play.Activated:Connect(function()
		open(loadout)
		Net.event("Loadout"):FireServer("Ask")
	end)
	local settings = title.node.Settings :: TextButton
	settings.Activated:Connect(function()
		SettingsMenu.open()
	end)

	local deathSeen = 0
	Net.event("Loadout").OnClientEvent:Connect(function(s: any)
		local wasAlive = state and state.alive
		state = s
		deployAt = os.clock() + (s.wait or 0)
		setTeam(s.kit)
		render()
		-- a death (the state the server sends as the soldier falls): the menu after a moment, the death seen first
		if wasAlive ~= false and s.alive == false and not title.gui.Enabled and not loadout.gui.Enabled then
			deathSeen += 1
			local mine = deathSeen
			task.delay(Classes.MenuAfterDeath, function()
				if mine == deathSeen and state and not state.alive and not title.gui.Enabled then
					open(loadout)
				end
			end)
		end
	end)

	-- deployed: the menus go, the game's camera comes back
	player.CharacterAdded:Connect(function()
		deathSeen += 1
		if state then
			state.alive = true
		end
		open(nil)
	end)

	RunService.RenderStepped:Connect(function()
		if loadout.gui.Enabled then
			local left = deployAt - os.clock()
			if left > 0 then
				deploy.Text = `Deploy in {math.ceil(left)}`
				paint(deploy, "field", "line", "textDim")
			else
				deploy.Text = "Deploy"
				paint(deploy, "selFill", "selLine", "selText")
			end
			-- the soldier turns slowly in its view
			local t = os.clock() * P.Turn
			local look = Vector3.new(0, P.Look, 0)
			local out = Vector3.new(math.sin(t) * P.Distance, P.Up, -math.cos(t) * P.Distance)
			viewCam.CFrame = CFrame.lookAt(look + out, look)
		end
		if menuOpen then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
	end)

	-- the join: the title screen (unless a soldier is already out, e.g. a respawn from the dev tools)
	if player.Character then
		state = { alive = true }
	else
		open(title)
		Net.event("Loadout"):FireServer("Ask") -- (the team line and the preview get ready meanwhile)
	end
end

return Menus
