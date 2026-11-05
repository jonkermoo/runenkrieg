--!strict
-- The frontline match, Normal mode (Config/Frontline, Rules/Frontline; user 2026-10-27: "a standard 5 stage territory
-- push between 2 sides") on the live map's sector chain (src/shared/LiveMap: Map 1 until a vote picks another;
-- Config/Maps/<key>.sectors: S1 the West HQ, the last the East HQ).
-- src/server/Modes starts and stops it. Each match draws two teams (Workspace's MatchTeams attribute,
-- Rules/Frontline.pair), one on each side; a soldier's side is their team's (the character's "Kit"). A match waits
-- until each side has its players, counts down, then plays: every Tick the soldiers alive and on their feet in each
-- sector's zone push its control by their lead, in soldiers' worths for the server's size (Rules/Frontline.unit; each
-- capture's time from the first push off the holder's end is published for the admin readout). Captures and
-- neutralisations pay each soldier of that side in the zone, a kill near your side's attacked sector pays a Defend,
-- and taking the enemy HQ wins (everyone on the winning side paid); then the post-match cutscene (Finale), the results
-- and the map vote (src/server/MapVote; the map put back behind it: built pieces cleared, buildings, trees and ground
-- restored), and a fresh match on the chosen map (sides reset, a new pair, everyone respawns). The pre-match cutscene
-- plays over the countdown (src/client/MatchCutscene, Config/Cutscenes).
-- Respawning goes in waves (Config/Frontline.Waves): one clock for both sides; a soldier who deploys stands in its side's
-- wave line (Rules/Frontline.slot), frozen and shielded, until the wave goes, then keeps the shield a moment. The line
-- stands at the side's spawn sector (Rules/Frontline.spawnSector: its HQ, in its spawn zone Map1.spawnZones, until the
-- first capture; then its frontmost, by the flag, or one back while the enemy leads there). Each side's sectors held
-- from its end are published (Config/Frontline.Artillery: a side down to its last `unlockAt` sectors may build the
-- howitzer, read by src/server/Build), and a badly outnumbered side is reinforced (src/server/Loadouts pays it more). The state is replicated as
-- attributes on Workspace's "Frontline" folder (Config/Frontline.FolderName, read by src/client/ModeHud). The sector
-- markers (src/dev/Greybox, shown by the admin's switch: src/server/Sectors) are coloured by owner and labelled with
-- control and head counts. The admin panel ends and restarts a match and takes a side's next sector
-- (src/server/DevTools).
-- Bot soldiers (src/server/Bots, tagged Config/Bots.Tag) play a side like players: they count in the zones and for a
-- match's start (not for the reinforcements), stand in the wave line (Frontline.deployBot) and are paid through
-- Frontline.onBotAward.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Frontline)
local CutCfg = require(Shared.Config.Cutscenes)
local CutRules = require(Shared.Rules.Cutscenes)
local NarratorClips = require(Shared.Config.NarratorClips)
local ResultsCfg = require(Shared.Config.Results)
local BotsCfg = require(Shared.Config.Bots)
local DamageCfg = require(Shared.Config.Damage)
local SectorCfg = require(Shared.Config.Sectors)
local Palette = require(Shared.Config.Palette)
local U = require(Shared.Config.Uniforms)
local LiveMap = require(Shared.LiveMap)
local Net = require(Shared.Net)
local Map = LiveMap.map
local Rules = require(Shared.Rules.Frontline)
local Build = require(script.Parent.Build)
local Damage = require(script.Parent.Damage)
local DevWorld = require(script.Parent.DevWorld)
local MapVote = require(script.Parent.MapVote)
local MatchStats = require(script.Parent.MatchStats)
local Kits = require(script.Parent.Kits)
local Ragdoll = require(script.Parent.Ragdoll)

local Frontline = {}

local sectors: { any } = Map.sectors -- (the live map's: useMap sets it again)

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true

local function ground(x: number, z: number): number
	local hit =
		workspace:Raycast(Vector3.new(x, Cfg.GroundRay.top, z), Vector3.new(0, -Cfg.GroundRay.depth, 0), terrainOnly)
	return if hit then hit.Position.Y else 0
end

local function alive(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return nil
	end
	return root
end

local state: Rules.State
local pair: { West: string, East: string }
local folder: Folder
local zoneY: { number } = {} -- each sector's ground at its point
local awardWatchers: { (Player, string) -> () } = {}
local botAwardWatchers: { (Model, string) -> () } = {}
local matchWatchers: { () -> () } = {}
-- while running: the match loop, the player hooks; set by the admin to end the match now
local thread: thread? = nil
local conns: { RBXScriptConnection } = {}
-- the next map streamed in by each player in the armory (Net "MapLoad"): the map asked for, and who hasn't said so yet
local loadingMap: string? = nil
local stillLoading: { [Player]: boolean } = {}
-- the flight toured by each player under the black before it (Net "MapTour"): the map, and who hasn't said so yet
local touring: string? = nil
local stillTouring: { [Player]: boolean } = {}
-- the war room's set built and preloaded by each player behind the victory screen (Net "SceneReady")
local readyScene: string? = nil
local stillReady: { [Player]: boolean } = {}
-- the admin's skip (Frontline.skipTo): every stage before this one cut short
local skipTo: string? = nil
local ORDER = { Fade = 1, Table = 2, Vote = 3, Loading = 4, Countdown = 5, Playing = 6 }
local ending = false
-- the admin's end into a map (Frontline.endInto): the winner it plays (nil: none) and the map the vote picks
local forced: { winner: Rules.Side?, map: string }? = nil
local starting = false -- set by the admin to skip the wait for players
-- each sector's first push off its holder's end (os.clock) while a capture is under way (the admin's capture time)
local pushedAt: { [number]: number } = {}
local captured = false -- any capture this match (spawns leave the HQs)
local latest: { { West: number, East: number } } = {} -- the last tick's soldiers in each zone
-- each side's lastStand guns open for the match (Rules/Frontline.latched) and the sectors it held at the last publish
local latch: { [string]: boolean } = { West = false, East = false }
local heldBefore: { [string]: number } = { West = 0, East = 0 }
local startOwners: { string } = {} -- each sector's owner at the match's start (Rules/Frontline.centerTaken)
local centerFell = false -- the center has fallen this match (both latches set once, then the admin's to change)
local waveAt: number? = nil -- the next wave's server time while the line holds (countdown and play)
local slots: { [string]: number } = { West = 0, East = 0 } -- the wave line's slots taken since the last wave
local holding: { [Model]: boolean } = {} -- the soldiers standing in a wave line
local frozen: { BasePart } = {} -- the roots anchored at a match's end, until the next match
local playedAt = 0 -- os.clock() when play began (the capture log's times)
local log: { { t: number, index: number, side: string } } = {} -- the match's captures, in order (the results' replay)

-- `fn(player, reason)` for each award (a Config/Classes.Earn key: Capture, Neutralise, Defend); `fn()` at each
-- match's start
function Frontline.onAward(fn: (Player, string) -> ())
	table.insert(awardWatchers, fn)
end
function Frontline.onMatchStart(fn: () -> ())
	table.insert(matchWatchers, fn)
end
-- `fn(bot, reason)` for each award to a bot soldier (src/server/Bots pays it)
function Frontline.onBotAward(fn: (Model, string) -> ())
	table.insert(botAwardWatchers, fn)
end

local function isPlayer(who: Player | Model): boolean
	return (who :: Instance):IsA("Player")
end

local function award(who: Player | Model, reason: string)
	if isPlayer(who) then
		for _, fn in awardWatchers do
			task.spawn(fn, who :: Player, reason)
		end
	else
		for _, fn in botAwardWatchers do
			task.spawn(fn, who :: Model, reason)
		end
	end
end

-- the bot soldiers on the map now
local function bots(): { Model }
	local out = {}
	for _, m in CollectionService:GetTagged(BotsCfg.Tag) do
		if m:IsA("Model") and m.Parent then
			table.insert(out, m)
		end
	end
	return out
end

-- the admin skips past `stage`
local function skipping(stage: string): boolean
	return skipTo ~= nil and (ORDER[skipTo :: string] or 0) > (ORDER[stage] or 0)
end

-- `seconds` of stage `stage` (cut short by the admin's skip past it)
local function holdStage(stage: string, seconds: number)
	local untilAt = os.clock() + seconds
	while os.clock() < untilAt and not skipping(stage) do
		task.wait(0.1)
	end
end

-- the players still loading in `list` (their names on the folder for the admin's load readout: WaitingAttribute)
local function pendingOf(list: { [Player]: boolean }): number
	local n, names = 0, {}
	for p in list do
		if p.Parent then
			n += 1
			table.insert(names, p.Name)
		end
	end
	table.sort(names)
	folder:SetAttribute(Cfg.WaitingAttribute, if n > 0 then table.concat(names, ", ") else nil)
	return n
end

local function phase(name: string, seconds: number?)
	local now = workspace:GetServerTimeNow()
	folder:SetAttribute("Phase", name)
	folder:SetAttribute("PhaseAt", now)
	folder:SetAttribute("PhaseEndsAt", if seconds then now + seconds else nil)
end

-- A dip to black between scenes (Config/Cutscenes.Dip): every screen darkens, and phase `name` starts once black.
local function dipTo(name: string, seconds: number?, kind: string?)
	local d = if kind == "Flight" then CutCfg.FlightDip else CutCfg.Dip
	folder:SetAttribute(Cfg.DipKindAttribute, kind)
	folder:SetAttribute(Cfg.DipAttribute, workspace:GetServerTimeNow() + d.out)
	task.wait(d.out)
	phase(name, seconds)
end

-- The black before the flight (Config/Cutscenes.FlightDip) held while every player's camera tours the flight unseen
-- (Net "MapTour": a map's textures and mesh detail load only once a camera looks at them; user 2026-11-04: "100% of
-- the map with no stuff still rendering"), Loading.tour at the most. The countdown then starts as the black's hold.
local function tourFlight()
	local d = CutCfg.FlightDip
	folder:SetAttribute(Cfg.DipKindAttribute, "Flight")
	folder:SetAttribute(Cfg.DipAttribute, workspace:GetServerTimeNow() + d.out)
	task.wait(d.out)
	table.clear(stillTouring)
	for _, p in Players:GetPlayers() do
		stillTouring[p] = true
	end
	touring = LiveMap.key()
	Net.event("MapTour"):FireAllClients(touring)
	local from = os.clock()
	while true do
		folder:SetAttribute(Cfg.DipAttribute, workspace:GetServerTimeNow()) -- (the black kept)
		local pending = pendingOf(stillTouring)
		if CutRules.loadOver(os.clock() - from, 0, Cfg.Loading.tour, pending) or skipping("Countdown") then
			break
		end
		task.wait(0.1)
	end
	touring = nil
	folder:SetAttribute(Cfg.WaitingAttribute, nil)
end

-- Every mesh and texture of map `key`'s model (content ids): each client preloads them all in the armory, the parts
-- it hasn't streamed in too.
local function assetsOf(key: string): { string }
	local seen: { [string]: boolean } = {}
	local out = {}
	local function add(id: any)
		if type(id) == "string" and id ~= "" and not seen[id] then
			seen[id] = true
			table.insert(out, id)
		end
	end
	local root = workspace:FindFirstChild(key)
	for _, d in (if root then root:GetDescendants() else {}) do
		if d:IsA("MeshPart") then
			add(d.MeshId)
			add(d.TextureID)
		elseif d:IsA("SpecialMesh") then
			add(d.MeshId)
			add(d.TextureId)
		elseif d:IsA("Decal") then -- (Textures too)
			add(d.Texture)
		elseif d:IsA("SurfaceAppearance") then
			pcall(function()
				add(d.ColorMap)
				add(d.NormalMap)
				add(d.RoughnessMap)
				add(d.MetalnessMap)
			end)
		end
	end
	return out
end

-- The side `player` plays on this life (nil: not in the match, e.g. a testing kit of a team that isn't playing).
local function sideOf(player: Player): Rules.Side?
	local character = player.Character
	return Rules.sideOf(pair, character and character:GetAttribute("Kit"))
end

-- the side a soldier's model plays on (a bot's, or a player's character)
local function sideOfModel(character: Model): Rules.Side?
	return Rules.sideOf(pair, character:GetAttribute("Kit"))
end

-- each side's spawn sector now (published as "<Side>Spawn": the loadout map's deploy ring)
-- (fixed for a wave by its first soldier in, so one wave's soldiers all stand in one line)
local waveSector: { [string]: number } = {}
local function spawnSector(side: Rules.Side): number
	if waveAt and waveSector[side] then
		return waveSector[side]
	end
	return Rules.spawnSector(state, side, captured, latest)
end

-- the wave line's centre and facing for `side`: at its own HQ in its spawn zone, else by the sector's flag, its zone's
-- point and the one behind it (Rules/Frontline.lineCentre, Line.back of the way back); facing the sector it attacks
local function lineOf(side: Rules.Side): (Vector3, Vector3)
	local i = spawnSector(side)
	local home = if side == "West" then 1 else #sectors
	local centre: Vector3
	if i == home then
		local r = Map.spawnZones[side]
		centre = Vector3.new((r.minX + r.maxX) / 2, 0, (r.minZ + r.maxZ) / 2)
	else
		local cx, cz = Rules.lineCentre(sectors, i, side, Cfg.Line)
		centre = Vector3.new(cx, 0, cz)
	end
	local aim = sectors[Rules.target(state, side) or i]
	local face = Vector3.new(aim.x - centre.X, 0, aim.z - centre.Z)
	if face.Magnitude < 1 then
		face = if side == "West" then Vector3.xAxis else -Vector3.xAxis
	end
	return centre, face.Unit
end

local everything = RaycastParams.new()
everything.FilterType = Enum.RaycastFilterType.Exclude
everything.IgnoreWater = false

-- the ground at a wave line slot: the highest under the feet (its middle and Line.foot studs round it, so a slope
-- never buries them; user 2026-11-01: "my body was in the ground"); nil when it isn't open dry ground (a roof, water,
-- a tree or a wall in the way)
local function openAt(x: number, z: number, skip: { Instance }): number?
	everything.FilterDescendantsInstances = skip
	local hit: RaycastResult? = nil
	local top = -math.huge
	for _, o in Rules.footprint(Cfg.Line.foot) do
		local h = workspace:Raycast(
			Vector3.new(x + o[1], Cfg.GroundRay.top, z + o[2]),
			Vector3.new(0, -Cfg.GroundRay.depth, 0),
			everything
		)
		if not h or h.Instance ~= workspace.Terrain or h.Material == Enum.Material.Water then
			return nil
		end
		top = math.max(top, h.Position.Y)
		hit = hit or h
	end
	if not hit then
		return nil
	end
	local c = Cfg.Line.clear
	local box = OverlapParams.new()
	box.FilterType = Enum.RaycastFilterType.Exclude
	box.FilterDescendantsInstances = skip
	box.RespectCanCollide = true
	local at = CFrame.new(hit.Position + Vector3.new(0, c[2] / 2 + 0.5, 0))
	if #workspace:GetPartBoundsInBox(at, Vector3.new(c[1], c[2], c[3]), box) > 0 then
		return nil
	end
	return top
end

-- the next open slot of `side`'s wave line: the ground under it (the feet) and a point to face
local function nextSlot(side: Rules.Side): (Vector3, Vector3)
	if waveAt and not waveSector[side] then
		waveSector[side] = spawnSector(side)
	end
	local centre, face = lineOf(side)
	local right = face:Cross(Vector3.yAxis)
	local skip: { Instance } = bots()
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	for _ = 1, Cfg.Line.tries do
		slots[side] += 1
		local r, b = Rules.slot(slots[side], Cfg.Line)
		local spot = centre + right * r - face * b
		local y = openAt(spot.X, spot.Z, skip)
		if y then
			local pos = Vector3.new(spot.X, y, spot.Z)
			return pos, pos + face
		end
	end
	local pos = Vector3.new(centre.X, ground(centre.X, centre.Z), centre.Z)
	return pos, pos + face
end

-- how far a soldier's root stands over its feet (its own legs, root and hip height)
local function standHeight(character: Model, root: BasePart): number
	local leg = character:FindFirstChild("Left Leg") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return (if leg then leg.Size.Y else 2) + root.Size.Y / 2 + (if humanoid then humanoid.HipHeight else 0)
end

-- the highest ground (terrain only) under a soldier standing at `x, z` (Rules.footprint)
local function groundUnder(x: number, z: number): number
	local top = -math.huge
	for _, o in Rules.footprint(Cfg.Line.foot) do
		top = math.max(top, ground(x + o[1], z + o[2]))
	end
	return top
end

-- every held soldier's feet back over the ground: the ground can rise under one waiting, anchored, in its line (dug
-- spoil, a crater's rim), and an anchored body can't climb out by itself
local function keepUp()
	for character in holding do
		local root = character.Parent and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local p = root.Position
			local feet = p.Y - standHeight(character, root)
			local up = Rules.liftNeeded(feet, groundUnder(p.X, p.Z), Cfg.Line.lift)
			if up > Cfg.Line.relift then
				character:PivotTo(character:GetPivot() + Vector3.new(0, up, 0))
			end
		end
	end
end
task.spawn(function()
	while true do
		task.wait(Cfg.Line.recheck)
		keepUp()
	end
end)

-- the shield round a soldier in the wave line, in its team's magic colour
local function shield(character: Model, root: BasePart)
	local old = character:FindFirstChild(Cfg.Shield.name)
	if old then
		old:Destroy()
	end
	local kit = character:GetAttribute("Kit")
	local c = (Palette.UI.Grimoire.Magic :: any)[kit] or { 230, 230, 230 }
	local ball = Instance.new("Part")
	ball.Name = Cfg.Shield.name
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * Cfg.Shield.size
	ball.Material = Enum.Material.ForceField
	ball.Color = Color3.fromRGB(c[1], c[2], c[3])
	ball.Transparency = Cfg.Shield.transparency
	ball.CanCollide, ball.CanQuery, ball.CanTouch, ball.Massless = false, false, false, true
	ball.CastShadow = false
	ball.CFrame = root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = ball, root
	weld.Parent = ball
	ball.Parent = character
	-- (gone at once when the soldier attacks and loses its protection: src/server/Damage)
	character:GetAttributeChangedSignal(DamageCfg.ProtectedAttribute):Connect(function()
		if character:GetAttribute(DamageCfg.ProtectedAttribute) == nil and ball.Parent then
			ball:Destroy()
		end
	end)
end

-- the wave goes: everyone in the line can move, the shield fading over Waves.shield
-- A match's end (on): every soldier, player or bot, anchored where it stands (the bots stop thinking: Frontline.over);
-- off: let go again.
local function freeze(on: boolean)
	for _, root in frozen do
		if root.Parent then
			root.Anchored = false
		end
	end
	table.clear(frozen)
	if not on then
		return
	end
	local function hold(character: Model?)
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and not root.Anchored then
			root.Anchored = true
			table.insert(frozen, root)
		end
	end
	for _, p in Players:GetPlayers() do
		hold(p.Character)
	end
	for _, m in bots() do
		hold(m)
	end
end

local function release()
	for character in holding do
		if not character.Parent then
			continue -- (died or left meanwhile)
		end
		character:SetAttribute(Cfg.HoldAttribute, nil)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = false
			-- (unless still held by something anchored, e.g. a test: the ownership calls would throw)
			if root:CanSetNetworkOwnership() then
				if CollectionService:HasTag(character, BotsCfg.Tag) then
					root:SetNetworkOwner(nil) -- (a bot stays the server's)
				else
					root:SetNetworkOwnershipAuto() -- (back to its player, as Roblox gives a character)
				end
			end
		end
		local ball = character:FindFirstChild(Cfg.Shield.name) :: BasePart?
		if ball then
			local fade = TweenService:Create(ball, TweenInfo.new(Cfg.Waves.shield), { Transparency = 1 })
			fade.Completed:Once(function()
				ball:Destroy()
			end)
			fade:Play()
		end
	end
	table.clear(holding)
end

-- stands `player`'s soldier in its side's wave line: frozen and shielded until the wave goes while one is due (the
-- countdown and play), else free on the spot (waiting for players, the results)
local function stand(character: Model, root: BasePart, side: Rules.Side): Vector3
	local feet, look = nextSlot(side)
	local up = Vector3.yAxis * (standHeight(character, root) + Cfg.Line.lift)
	local pos = feet + up
	if waveAt and not root.Anchored then
		-- (the server holds the body while it stands in the line: its player's client can't move it meanwhile)
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	character:PivotTo(CFrame.lookAt(pos, look + up))
	root.AssemblyLinearVelocity = Vector3.zero
	if waveAt then
		local left = (waveAt :: number) - workspace:GetServerTimeNow()
		root.Anchored = true
		character:SetAttribute(Cfg.HoldAttribute, waveAt)
		-- empty hands until the wave goes (user 2026-11-01: "nothing can be equipped"): a player's tool taken out goes
		-- back to the backpack (a bot puts its own away, src/server/Bots)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local player = Players:GetPlayerFromCharacter(character)
		if humanoid and player then
			humanoid:UnequipTools()
			local guard: RBXScriptConnection
			guard = character.ChildAdded:Connect(function(child)
				if character:GetAttribute(Cfg.HoldAttribute) == nil then
					guard:Disconnect()
				elseif child:IsA("Tool") then
					task.defer(function()
						local backpack = player:FindFirstChildOfClass("Backpack")
						if backpack and child.Parent == character then
							child.Parent = backpack
						end
					end)
				end
			end)
		end
		Damage.protect(character, math.max(left, 0) + Cfg.Waves.shield)
		shield(character, root)
		holding[character] = true
		if humanoid then
			humanoid.Died:Once(function()
				holding[character] = nil
			end)
		end
	end
	return pos
end

local function spawnAt(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local side = sideOf(player)
	if not character or not root or not side then
		return
	end
	local pos = stand(character, root, side)
	task.spawn(function()
		pcall(function()
			player:RequestStreamAroundAsync(pos)
		end)
	end)
end

local function join(player: Player)
	local function spawned(character: Model)
		character:WaitForChild("HumanoidRootPart", Cfg.SpawnWait)
		task.wait() -- after Roblox has stood it on a spawn (and Kits has dressed it)
		spawnAt(player)
	end
	table.insert(conns, player.CharacterAdded:Connect(spawned))
	if player.Character then
		task.spawn(spawned, player.Character)
	end
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- the sector markers (when built) coloured by owner, labelled with control and who's in the zone
local function showMarkers(counts: { { West: number, East: number } })
	local root = workspace:FindFirstChild(LiveMap.key())
	local markers = root and root:FindFirstChild("Sectors")
	if not markers then
		return
	end
	for i, s in sectors do
		local model = markers:FindFirstChild(`Point_{s.id}`)
		if model then
			local color = rgb(SectorCfg.Marker.ColorRGB[state.owner[i]])
			for _, p in model:GetChildren() do
				if p:IsA("BasePart") then
					p.Color = color
				end
			end
			local label = model:FindFirstChild("Label", true)
			local text = label and label:FindFirstChildOfClass("TextLabel")
			if text then
				local c = state.control[i]
				text.Text = `{s.id} {math.round(c * 100)} W{counts[i].West} E{counts[i].East}`
			end
		end
	end
end

local function publish(
	counts: { { West: number, East: number } },
	unit: number?,
	heads: { { West: number, East: number } }?
)
	local rates = Rules.rates(state, Cfg, counts, unit)
	for i, s in sectors do
		local f = folder:FindFirstChild(s.id)
		if f then
			f:SetAttribute(Cfg.RateAttribute, rates[i]) -- (control per second now: the admin readout)
			f:SetAttribute("Owner", state.owner[i])
			f:SetAttribute("Control", state.control[i])
			f:SetAttribute("West", counts[i].West)
			f:SetAttribute("East", counts[i].East)
			f:SetAttribute("West" .. Cfg.HeadsSuffix, (heads or counts)[i].West)
			f:SetAttribute("East" .. Cfg.HeadsSuffix, (heads or counts)[i].East)
		end
	end
	-- (once the center falls, both sides keep the lastStand guns: Config/Frontline.Artillery)
	local falls = not centerFell and Rules.centerTaken(startOwners, state.owner)
	centerFell = centerFell or falls
	for _, side in { "West", "East" } do
		local held = Rules.held(state, side)
		latch[side] = Rules.latched(Cfg.Artillery, latch[side], heldBefore[side], held) or falls
		heldBefore[side] = held
		folder:SetAttribute(side .. Cfg.HeldAttribute, held)
		folder:SetAttribute(side .. Cfg.LatchAttribute, latch[side])
		folder:SetAttribute(side .. Cfg.SpawnAttribute, spawnSector(side))
		folder:SetAttribute(side .. Cfg.LineAttribute, (lineOf(side)))
	end
	showMarkers(counts)
end

local function empty(): { { West: number, East: number } }
	local counts = {}
	for i in sectors do
		counts[i] = { West = 0, East = 0 }
	end
	return counts
end

-- each sector's soldiers in its zone by side, weighed (Rules/Frontline.weight: a player 1, a bot Config BotWeight), the
-- soldiers in each zone (players and bots), and their heads by side (unweighed: the bots' planning)
local function occupancy(): (
	{ { West: number, East: number } },
	{ { Player | Model } },
	{ { West: number, East: number } }
)
	local counts, inside, byHead = empty(), {}, empty()
	for i in sectors do
		inside[i] = {}
	end
	local function count(who: Player | Model, character: Model?, root: BasePart?, side: Rules.Side?)
		if root and side and character and not Ragdoll.active(character) and not Damage.protected(character) then
			local feet = root.Position - Vector3.new(0, Cfg.FeetBelowRoot, 0)
			for i, s in sectors do
				if Rules.inZone(feet.X - s.x, feet.Z - s.z, feet.Y - zoneY[i], s.radius, Cfg.Height) then
					counts[i][side] += Rules.weight(Cfg, not isPlayer(who))
					byHead[i][side] += 1
					table.insert(inside[i], who)
					break
				end
			end
		end
	end
	for _, p in Players:GetPlayers() do
		count(p, p.Character, alive(p), sideOf(p))
	end
	for _, m in bots() do
		local humanoid = m:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			count(m, m, m:FindFirstChild("HumanoidRootPart") :: BasePart?, sideOfModel(m))
		end
	end
	return counts, inside, byHead
end

-- how many players each side has (by their next life's team); `withBots`: and its bot soldiers (a match's start counts
-- them, the reinforcements don't)
local function heads(withBots: boolean?): (number, number)
	local w, e = 0, 0
	local function add(side: Rules.Side?)
		if side == "West" then
			w += 1
		elseif side == "East" then
			e += 1
		end
	end
	for _, p in Players:GetPlayers() do
		add(Rules.sideOf(pair, Kits.next(p)))
	end
	if withBots then
		for _, m in bots() do
			add(sideOfModel(m))
		end
	end
	return w, e
end

-- each side's strength, weighed as in a zone (Rules/Frontline.weight: a player 1, a bot BotWeight), living or not:
-- the server's size for the capture speed (Rules/Frontline.unit)
local function strength(): (number, number)
	local s = { West = 0, East = 0 }
	for _, p in Players:GetPlayers() do
		local side = Rules.sideOf(pair, Kits.next(p))
		if side then
			s[side] += Rules.weight(Cfg, false)
		end
	end
	for _, m in bots() do
		local side = sideOfModel(m)
		if side then
			s[side] += Rules.weight(Cfg, true)
		end
	end
	return s.West, s.East
end

local function setWave(at: number?)
	table.clear(waveSector)
	waveAt = at
	slots.West, slots.East = 0, 0
	folder:SetAttribute(Cfg.WaveAttribute, at)
end

-- The match moves to map `key` (the vote's pick): Workspace's MapAttribute names it (LiveMap, so every module reads
-- its config from now on), and the sectors, their zones' ground and the sector folders are its own. (src/server/
-- Flagpoles stands its poles again on the attribute's change.)
local function useMap(key: string)
	if key == LiveMap.key() then
		return
	end
	workspace:SetAttribute(Cfg.MapAttribute, key)
	sectors = Map.sectors
	table.clear(zoneY)
	for _, f in folder:GetChildren() do
		if f:IsA("Folder") and f:GetAttribute("Index") then
			f:Destroy()
		end
	end
	for i, s in sectors do
		zoneY[i] = ground(s.x, s.z)
		local f = Instance.new("Folder")
		f.Name = s.id
		f:SetAttribute("Index", i)
		f.Parent = folder
	end
end

-- A fresh match. `reset`: the map is put back first (user 2026-10-29: everything): every built piece cleared, the
-- buildings, trees and ground (craters, mud) as they were when the match mode started (src/server/DevWorld).
local function putBack()
	release()
	Build.clear()
	DevWorld.undo()
end

local function newMatch(reset: boolean?)
	if reset then
		putBack()
	end
	MapVote.clear(folder)
	pair = Rules.mapPair(LiveMap.get(LiveMap.key()).pair, U.Teams, Cfg.AlwaysTeam, math.random(), math.random())
	workspace:SetAttribute(Cfg.TeamsAttribute, Rules.pairText(pair))
	state = Rules.new(sectors)
	ending = false
	forced = nil
	captured = false
	latest = empty()
	table.clear(log)
	for _, side in { "West", "East" } do
		latch[side], heldBefore[side] = false, Rules.held(state, side)
	end
	startOwners, centerFell = table.clone(state.owner), false
	setWave(nil)
	folder:SetAttribute("West", pair.West)
	folder:SetAttribute("East", pair.East)
	folder:SetAttribute("Winner", nil)
	folder:SetAttribute(Cfg.LastCaptureAttribute, nil)
	folder:SetAttribute(Cfg.UnitAttribute, nil)
	folder:SetAttribute(Cfg.ReinforcedAttribute, nil)
	publish(empty())
end

local function run()
	while true do
		-- waiting for players, then the countdown (sectors hold still; points start over)
		phase("Waiting")
		for _, fn in matchWatchers do
			task.spawn(fn)
		end
		while not ending do
			local w, e = heads(true)
			if starting or Rules.ready(w, e, Cfg.MinPerSide) then
				break
			end
			task.wait(Cfg.Tick)
		end
		starting = false
		if not ending then
			-- everyone into their HQ's wave line; the first wave goes when the countdown ends. After a match the
			-- flight over the map plays over it (src/client/MatchCutscene); a fresh server (nothing played yet: no
			-- narrator's subject) shows a short loading screen instead and dips to black into the game at the whistle
			-- (src/client/EndScenes; user 2026-11-03)
			local fresh = folder:GetAttribute(Cfg.SpeechAttribute) == nil
			-- (after a match: a longer black into the flight, which starts as it clears: Rules/Cutscenes.flightSeconds)
			local seconds = if fresh
				then Cfg.FreshCountdownSeconds
				else CutRules.flightSeconds(Cfg.CountdownSeconds, CutCfg.FlightDip)
			if fresh then
				dipTo("Countdown", seconds)
			else
				tourFlight()
				phase("Countdown", seconds)
			end
			local start = workspace:GetServerTimeNow() + seconds
			if fresh then
				task.delay(CutCfg.Dip.hold + CutCfg.Dip.inn, function()
					if folder.Parent and folder:GetAttribute("Phase") == "Countdown" then
						folder:SetAttribute(Cfg.DipAttribute, start)
					end
				end)
			end
			setWave(start) -- (the lines start empty: slots from 1)
			for _, p in Players:GetPlayers() do
				local character = p.Character
				if alive(p) and character and not holding[character] then
					spawnAt(p)
				end
			end
			for _, m in bots() do
				if not holding[m] then
					Frontline.deployBot(m)
				end
			end
			-- (the admin's "Start now" cuts it short: Frontline.begin)
			while not starting and not ending and workspace:GetServerTimeNow() < start and not skipping("Countdown") do
				task.wait(0.1)
			end
			starting = false
			skipTo = nil
			release()
			folder:SetAttribute(Cfg.SpeechAttribute, nil) -- (the narrator has spoken)
			setWave(Rules.nextWave(start, Cfg.Waves.every, workspace:GetServerTimeNow() + 0.05))
			phase("Playing")
			playedAt = os.clock()
		end
		local winner: Rules.Side? = nil
		local last = os.clock()
		table.clear(pushedAt)
		while not winner and not ending do
			task.wait(Cfg.Tick)
			local dt = os.clock() - last
			last = os.clock()
			if waveAt and workspace:GetServerTimeNow() >= (waveAt :: number) then
				release()
				setWave((waveAt :: number) + Cfg.Waves.every)
			end
			local w, e = heads()
			folder:SetAttribute(Cfg.ReinforcedAttribute, Rules.reinforced(Cfg.Reinforcements, w, e))
			local counts, inside, inZone = occupancy()
			latest = inZone -- (the spawn choice by head, as before; the weights are the capture's)
			local unit = Rules.unit(Cfg, strength())
			folder:SetAttribute(Cfg.UnitAttribute, unit)
			for _, ev in Rules.step(state, Cfg, counts, dt, unit) do
				if ev.kind == "Captured" then
					local from = pushedAt[ev.index]
					if from then
						folder:SetAttribute(Cfg.LastCaptureAttribute, math.round((last - from) * 10) / 10)
					end
					captured = true
					table.insert(log, { t = os.clock() - playedAt, index = ev.index, side = ev.side })
				end
				local reason = if ev.kind == "Captured" then "Capture" else "Neutralise"
				for _, who in inside[ev.index] do
					local side = if isPlayer(who) then sideOf(who :: Player) else sideOfModel(who :: Model)
					if side == ev.side then
						award(who, reason)
					end
				end
			end
			-- a capture under way: from the first push off the holder's end until it is taken or back at that end
			-- (a sector just neutralised sits at its neutral rest while the push goes on: it starts over only once nobody
			-- leads there)
			for i in sectors do
				if state.control[i] == Rules.rest(state.owner[i]) then
					if state.owner[i] ~= "Neutral" or counts[i].West == counts[i].East then
						pushedAt[i] = nil
					end
				elseif not pushedAt[i] then
					pushedAt[i] = last - dt -- (the tick that moved it)
				end
			end
			publish(counts, unit, inZone)
			winner = Rules.winner(state)
		end
		local force = forced
		if force then
			winner = force.winner
		end
		-- (no Win award since the marks rebalance, user 2026-11-05: "drop"; the points reset with the next match)
		folder:SetAttribute("Winner", winner)
		release()
		setWave(nil)
		folder:SetAttribute(Cfg.ReinforcedAttribute, nil)
		-- the end (Config/Cutscenes; user 2026-11-02): everyone frozen where they stand and the screen faded to the
		-- winner's colour, the after-action report on the battle table (the results are sent now), the winners' vote on
		-- the map board, then the armory while the map is put back and moved to the pick: at least as long as the
		-- narrator's first part. The narrator's subject stays on the folder until the next countdown has played.
		freeze(true)
		local winnerKit: string? = if winner then pair[winner] else nil
		local loserKit: string? = if winner then pair[if winner == "West" then "East" else "West"] else nil
		local played = LiveMap.key()
		folder:SetAttribute(Cfg.SpeechAttribute, `{winnerKit or "none"},{played},{loserKit or "none"}`)
		-- the kit each player fought in, for their side's script in the armory (Rules/Cutscenes.scriptOf)
		for _, p in Players:GetPlayers() do
			local kit = Kits.next(p)
			p:SetAttribute(Cfg.MatchKitAttribute, if Rules.sideOf(pair, kit) then kit else nil)
		end
		-- the victory screen (user 2026-11-04: "play the victory screen for a lot longer. use that victory screen to load
		-- the summary war room scene"): Victory.least at the least, and until every player's war room set is built and
		-- preloaded behind it (Net "SceneReady"), Victory.max at the most
		phase("Fade", Cfg.Victory.least)
		table.clear(stillReady)
		for _, p in Players:GetPlayers() do
			stillReady[p] = true
		end
		readyScene = "Table"
		-- the table until its replay and report are done (Rules/Cutscenes.tableSeconds: every client draws the same)
		local tableSeconds = CutRules.tableSeconds(
			CutCfg.Table,
			math.min(#log, ResultsCfg.Replay.most),
			CutRules.reportLines(CutCfg.Table.top3),
			winner ~= nil
		)
		MatchStats.send({
			mode = "Normal",
			winner = winnerKit,
			log = table.clone(log),
			length = os.clock() - playedAt,
			map = played,
			top = CutCfg.Table.top3,
			endsAt = workspace:GetServerTimeNow() + Cfg.Victory.least + CutCfg.Dip.out + tableSeconds,
		}, function(p: Player): string?
			return Kits.next(p)
		end)
		local victoryFrom = os.clock()
		while
			not CutRules.loadOver(os.clock() - victoryFrom, Cfg.Victory.least, Cfg.Victory.max, pendingOf(stillReady))
			and not skipping("Fade")
		do
			task.wait(0.1)
		end
		readyScene = nil
		folder:SetAttribute(Cfg.WaitingAttribute, nil)
		dipTo("Table", tableSeconds)
		holdStage("Table", tableSeconds)
		local pick = if force then force.map else played
		local offer = MapVote.offer()
		if force and not table.find(offer, force.map) then
			offer[#offer] = force.map -- (its sheet on the board, to be stamped)
		end
		if #offer > 1 then
			local winners = false
			for _, p in Players:GetPlayers() do
				winners = winners or (winner ~= nil and Rules.sideOf(pair, Kits.next(p)) == winner)
			end
			phase("Vote", Cfg.VoteSeconds)
			MapVote.open(folder, offer, function(p: Player): boolean
				return CutRules.maySign(Rules.sideOf(pair, Kits.next(p)), winner, winners)
			end)
			holdStage("Vote", Cfg.VoteSeconds)
			pick = MapVote.close(folder, math.random(), if force then force.map else nil) or played
			holdStage("Vote", CutCfg.Vote.pick.hold) -- (the arm stamps NEXT on every screen)
		end
		-- the armory lasts the longer of the two sides' scripts
		local nations: { [string]: string } = {}
		for kit, k in U.Kits :: any do
			nations[kit] = k.team
		end
		local S = CutCfg.Speech
		local spoken = 0
		for _, side in { { winnerKit, "won" }, { loserKit, "lost" } } do
			local one = CutRules.partOne(S, side[1], side[2] :: any, played, nations, LiveMap.get(played).name)
			spoken = math.max(spoken, CutRules.speechSeconds(one, S.wordsPerSecond, S.gap, NarratorClips.clips))
		end
		local least = math.clamp(spoken, Cfg.Loading.least, Cfg.Loading.max)
		dipTo("Loading", least)
		local loading = os.clock()
		putBack()
		useMap(pick)
		newMatch()
		-- every player streams in what the next flight shows: its narrator's part waits for them all (user
		-- 2026-11-03), or Loading.max at the most
		table.clear(stillLoading)
		for _, p in Players:GetPlayers() do
			stillLoading[p] = true
		end
		loadingMap = pick
		Net.event("MapLoad"):FireAllClients(pick, assetsOf(pick))
		while true do
			local pending = pendingOf(stillLoading)
			if CutRules.loadOver(os.clock() - loading, least, Cfg.Loading.max, pending) or skipping("Loading") then
				break
			end
			task.wait(0.1)
		end
		loadingMap = nil
		folder:SetAttribute(Cfg.WaitingAttribute, nil)
		freeze(false)
		task.wait() -- (src/server/Deploy splits everyone over the new pair first)
		for _, p in Players:GetPlayers() do
			if alive(p) then
				task.spawn(function()
					p:LoadCharacter()
				end)
			end
		end
	end
end

-- A kill (src/server/Loadouts.onKill): a Defend for `killer` when it or the victim was near the killer's side's
-- sector while the enemy attacks it.
function Frontline.killed(killer: Player, victim: Model)
	if not thread or folder:GetAttribute("Phase") ~= "Playing" then
		return
	end
	local side = sideOf(killer)
	local a = alive(killer)
	local v = victim:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not side then
		return
	end
	local spots = {}
	for _, part in { a, v } do
		if part then
			table.insert(spots, { part.Position.X, part.Position.Z })
		end
	end
	if Rules.defends(state, sectors, side, spots, Cfg.DefendReach) then
		award(killer, "Defend")
	end
end

-- Stands bot soldier `m` (src/server/Bots) in its side's wave line, as a player's soldier is on spawning: held and
-- shielded until the wave goes while one is due, else free on the spot.
function Frontline.deployBot(m: Model)
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = m:FindFirstChildOfClass("Humanoid")
	local side = if thread then sideOfModel(m) else nil
	if root and side and humanoid and humanoid.Health > 0 then
		stand(m, root, side)
	end
end

-- Whether the match is running (the server's mode is Normal).
-- Whether the match is over and its end is playing (the fade, the table, the vote, the armory): nobody fights.
local OVER = { Fade = true, Table = true, Vote = true, Loading = true }
function Frontline.over(): boolean
	local ph = thread and folder and folder:GetAttribute("Phase")
	return type(ph) == "string" and OVER[ph] == true
end

function Frontline.running(): boolean
	return thread ~= nil
end

-- Starts the match (src/server/Modes, switching to Normal): false with Map 1 unbuilt.
function Frontline.start(): boolean
	if thread then
		return false
	end
	if not workspace:FindFirstChild(LiveMap.key()) then
		warn(`[Frontline] the map isn't built: Greybox.build("{LiveMap.key()}")`)
		return false
	end
	sectors = Map.sectors
	table.clear(zoneY)
	folder = Instance.new("Folder")
	folder.Name = Cfg.FolderName
	for i, s in sectors do
		zoneY[i] = ground(s.x, s.z)
		local f = Instance.new("Folder")
		f.Name = s.id
		f:SetAttribute("Index", i)
		f.Parent = folder
	end
	folder.Parent = workspace
	-- the map as it is now is what each new match puts back
	DevWorld.ensure()
	-- (the first pair before anyone joins, so their first kit is rolled from it)
	newMatch()
	table.insert(conns, Players.PlayerAdded:Connect(join))
	table.insert(
		conns,
		Net.event("MapLoad").OnServerEvent:Connect(function(p: Player, key: unknown)
			if loadingMap ~= nil and key == loadingMap then
				stillLoading[p] = nil
			end
		end)
	)
	table.insert(
		conns,
		Net.event("SceneReady").OnServerEvent:Connect(function(p: Player, scene: unknown)
			if readyScene ~= nil and scene == readyScene then
				stillReady[p] = nil
			end
		end)
	)
	table.insert(
		conns,
		Net.event("MapTour").OnServerEvent:Connect(function(p: Player, key: unknown)
			if touring ~= nil and key == touring then
				stillTouring[p] = nil
			end
		end)
	)
	for _, p in Players:GetPlayers() do
		join(p)
	end
	thread = task.spawn(run)
	return true
end

-- Stops the match and takes its state away (src/server/Modes, switching away from Normal).
function Frontline.stop()
	if not thread then
		return
	end
	task.cancel(thread :: thread)
	thread = nil
	release()
	freeze(false)
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	folder:Destroy()
	workspace:SetAttribute(Cfg.TeamsAttribute, nil)
	for _, p in Players:GetPlayers() do
		Kits.reroll(p)
	end
end

-- Admin: a fresh match now (sides reset, a new pair, waiting again; nobody respawns until they die).
function Frontline.restart()
	skipTo, readyScene = nil, nil
	if thread then
		task.cancel(thread :: thread)
		freeze(false)
		folder:SetAttribute(Cfg.SpeechAttribute, nil)
		newMatch(true)
		thread = task.spawn(run)
	end
end

-- Admin: the match moves to map `key` now (it must be built: src/dev/Greybox): a fresh match there, the map put back,
-- everyone alive deployed again on it (the bots by src/server/Bots: the match start respawns each on the new map; killed
-- here as well, the new bodies died before their death was hooked up and never came back).
function Frontline.switchMap(key: string): boolean
	if not thread or not LiveMap.built(key) then
		return false
	end
	task.cancel(thread :: thread)
	putBack()
	useMap(key)
	newMatch()
	thread = task.spawn(run)
	task.defer(function()
		for _, p in Players:GetPlayers() do
			if alive(p) then
				task.spawn(function()
					p:LoadCharacter()
				end)
			end
		end
	end)
	return true
end

-- Admin: the match starts now, without waiting for each side's players (a solo test) or the rest of the countdown
function Frontline.begin()
	local now = if thread then folder:GetAttribute("Phase") else nil
	if now == "Waiting" or now == "Countdown" then
		starting = true
	end
end

-- Admin: the match ends now as `result` for `player`'s side ("Win", "Lose" or "None"; the West's for a player with
-- none) and plays its whole end, the vote picking map `key` (it must be built). False outside a match or once its
-- end has begun.
function Frontline.endInto(player: Player, result: string, key: string): boolean
	local ph = if thread then folder:GetAttribute("Phase") else nil
	if not thread or not LiveMap.built(key) or (type(ph) == "string" and OVER[ph]) then
		return false
	end
	local mine: Rules.Side = sideOf(player) or Rules.sideOf(pair, Kits.next(player)) or "West"
	local theirs: Rules.Side = if mine == "West" then "East" else "West"
	forced = {
		winner = if result == "Win" then mine elseif result == "Lose" then theirs else nil,
		map = key,
	}
	ending = true
	return true
end

-- Admin: the match ends now with no winner (the results, then the next match).
function Frontline.finish()
	if thread then
		ending = true
	end
end

-- Admin: on to `stage` of the match's loop now (a key of ORDER: "Fade" the victory screen, "Table" the war room,
-- "Vote", "Loading" the armory, "Countdown" the flight, "Playing"): every stage before it cut short; from play into
-- the end's stages the match ends first (no winner). False when the stage is unknown or already behind.
function Frontline.skipTo(stage: string): boolean
	local ph = if thread then folder:GetAttribute("Phase") else nil
	if not thread or not ORDER[stage] or type(ph) ~= "string" then
		return false
	end
	if stage == "Playing" and (ph == "Waiting" or ph == "Countdown") then
		starting = true
		return true
	end
	if ph == "Playing" or ph == "Waiting" then
		if stage == "Playing" then
			return false
		end
		ending = true
	elseif (ORDER[ph] or 0) >= ORDER[stage] then
		return false
	end
	skipTo = if stage == "Fade" then nil else stage
	return true
end

-- Admin: `side` takes sector `index` now (counts as a capture; no points paid). False
-- outside play or with no such sector.
function Frontline.capture(side: Rules.Side, index: number): boolean
	if not thread or folder:GetAttribute("Phase") ~= "Playing" or not sectors[index] or state.owner[index] == side then
		return false
	end
	state.owner[index] = side
	state.control[index] = Rules.rest(side)
	captured = true
	table.insert(log, { t = os.clock() - playedAt, index = index, side = side })
	return true
end

-- Admin: `side`'s lastStand guns open for the rest of the match, or locked by the count again (Config/Frontline.Artillery).
function Frontline.setLatch(side: Rules.Side, on: boolean)
	latch[side] = on
	folder:SetAttribute(side .. Cfg.LatchAttribute, on)
end

-- Admin: `side` takes the sector it is attacking now (the front moves one sector).
function Frontline.push(side: Rules.Side): boolean
	local t = thread and Rules.target(state, side)
	return t ~= nil and Frontline.capture(side, t)
end

-- Admin: `player`'s side takes the sector it is attacking now.
function Frontline.take(player: Player)
	local side = sideOf(player)
	if side then
		Frontline.push(side)
	end
end

return Frontline
