--!strict
-- The frontline match, Normal mode (Config/Frontline, Rules/Frontline; user 2026-10-27: "a standard 5 stage territory
-- push between 2 sides") on Map 1's sector chain (Config/Maps/Map1.sectors: S1 the West HQ, S5 the East HQ).
-- src/server/Modes starts and stops it. Each match draws two teams (Workspace's MatchTeams attribute,
-- Rules/Frontline.pair), one on each side; a soldier's side is their team's (the character's "Kit"). A match waits
-- until each side has its players, counts down, then plays: every Tick the soldiers alive and on their feet in each
-- sector's zone push its control, faster the longer the front has stood still (momentum). Captures and
-- neutralisations pay each soldier of that side in the zone, a kill near your side's attacked sector pays a Defend,
-- and taking the enemy HQ wins (everyone on the winning side paid); then the results and a fresh match (the map put
-- back: built pieces cleared, buildings, trees and ground restored; sides reset, a new pair, everyone respawns).
-- Respawning goes in waves (Config/Frontline.Waves): one clock for both sides; a soldier who deploys stands in its side's
-- wave line (Rules/Frontline.slot), frozen and shielded, until the wave goes, then keeps the shield a moment. The line
-- stands at the side's spawn sector (Rules/Frontline.spawnSector: its HQ, in its spawn zone Map1.spawnZones, until the
-- first capture; then its frontmost, by the flag, or one back while the enemy leads there). Each sector lost raises
-- both sides' artillery level (Config/Frontline.Artillery, read by src/server/Build), and a badly outnumbered side is
-- reinforced (src/server/Loadouts pays it more). The state is replicated as
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
local BotsCfg = require(Shared.Config.Bots)
local DamageCfg = require(Shared.Config.Damage)
local SectorCfg = require(Shared.Config.Sectors)
local Palette = require(Shared.Config.Palette)
local U = require(Shared.Config.Uniforms)
local Map = require(Shared.Config.Maps.Map1)
local Rules = require(Shared.Rules.Frontline)
local Build = require(script.Parent.Build)
local Damage = require(script.Parent.Damage)
local DevWorld = require(script.Parent.DevWorld)
local MatchStats = require(script.Parent.MatchStats)
local Kits = require(script.Parent.Kits)
local Ragdoll = require(script.Parent.Ragdoll)

local Frontline = {}

local sectors: { any } = Map.sectors

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
local ending = false
local starting = false -- set by the admin to skip the wait for players
local still = 0 -- seconds since the last capture (the momentum)
local captured = false -- any capture this match (spawns leave the HQs)
local lost = 0 -- sectors lost this match (the artillery level)
local latest: { { West: number, East: number } } = {} -- the last tick's soldiers in each zone
local waveAt: number? = nil -- the next wave's server time while the line holds (countdown and play)
local slots: { [string]: number } = { West = 0, East = 0 } -- the wave line's slots taken since the last wave
local holding: { [Model]: boolean } = {} -- the soldiers standing in a wave line
local playedAt = 0 -- os.clock() when play began (the capture log's times)
local log: { { t: number, index: number, side: string } } = {} -- the match's captures, in order (the results' replay)

-- `fn(player, reason)` for each award (a Config/Classes.Earn key: Capture, Neutralise, Defend, Win); `fn()` at each
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

local function phase(name: string, seconds: number?)
	folder:SetAttribute("Phase", name)
	folder:SetAttribute("PhaseEndsAt", if seconds then workspace:GetServerTimeNow() + seconds else nil)
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
-- edge plus Line.edge toward the side's own end; facing the sector it attacks
local function lineOf(side: Rules.Side): (Vector3, Vector3)
	local i = spawnSector(side)
	local home = if side == "West" then 1 else #sectors
	local s = sectors[i]
	local centre: Vector3
	if i == home then
		local r = Map.spawnZones[side]
		centre = Vector3.new((r.minX + r.maxX) / 2, 0, (r.minZ + r.maxZ) / 2)
	else
		local back = sectors[if side == "West" then i - 1 else i + 1]
		local d = Vector3.new(back.x - s.x, 0, back.z - s.z).Unit
		centre = Vector3.new(s.x, 0, s.z) + d * (s.radius + Cfg.Line.edge)
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
	local f = Cfg.Line.foot
	local hit: RaycastResult? = nil
	local top = -math.huge
	for _, o in { { 0, 0 }, { f, 0 }, { -f, 0 }, { 0, f }, { 0, -f } } do
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
local function release()
	for character in holding do
		if not character.Parent then
			continue -- (died or left meanwhile)
		end
		character:SetAttribute(Cfg.HoldAttribute, nil)
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = false
			if CollectionService:HasTag(character, BotsCfg.Tag) then
				root:SetNetworkOwner(nil) -- (a bot stays the server's)
			else
				root:SetNetworkOwnershipAuto() -- (back to its player, as Roblox gives a character)
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
	local root = workspace:FindFirstChild(Cfg.MapKey)
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

local function publish(counts: { { West: number, East: number } })
	for i, s in sectors do
		local f = folder:FindFirstChild(s.id)
		if f then
			f:SetAttribute("Owner", state.owner[i])
			f:SetAttribute("Control", state.control[i])
			f:SetAttribute("West", counts[i].West)
			f:SetAttribute("East", counts[i].East)
		end
	end
	for _, side in { "West", "East" } do
		folder:SetAttribute(side .. Cfg.SpawnAttribute, spawnSector(side))
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

-- each sector's soldiers in its zone by side, and the soldiers in each zone (players and bots)
local function occupancy(): ({ { West: number, East: number } }, { { Player | Model } })
	local counts, inside = empty(), {}
	for i in sectors do
		inside[i] = {}
	end
	local function count(who: Player | Model, character: Model?, root: BasePart?, side: Rules.Side?)
		if root and side and character and not Ragdoll.active(character) and not Damage.protected(character) then
			local feet = root.Position - Vector3.new(0, Cfg.FeetBelowRoot, 0)
			for i, s in sectors do
				if Rules.inZone(feet.X - s.x, feet.Z - s.z, feet.Y - zoneY[i], s.radius, Cfg.Height) then
					counts[i][side] += 1
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
	return counts, inside
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

local function setWave(at: number?)
	table.clear(waveSector)
	waveAt = at
	slots.West, slots.East = 0, 0
	folder:SetAttribute(Cfg.WaveAttribute, at)
end

-- A fresh match. `reset`: the map is put back first (user 2026-10-29: everything): every built piece cleared, the
-- buildings, trees and ground (craters, mud) as they were when the match mode started (src/server/DevWorld).
local function newMatch(reset: boolean?)
	if reset then
		release()
		Build.clear()
		DevWorld.undo()
	end
	pair = Rules.pair(U.Teams, Cfg.AlwaysTeam, math.random(), math.random())
	workspace:SetAttribute(Cfg.TeamsAttribute, Rules.pairText(pair))
	state = Rules.new(sectors)
	ending = false
	captured, lost = false, 0
	latest = empty()
	table.clear(log)
	setWave(nil)
	folder:SetAttribute("West", pair.West)
	folder:SetAttribute("East", pair.East)
	folder:SetAttribute("Winner", nil)
	folder:SetAttribute("Momentum", 1)
	folder:SetAttribute(Cfg.LevelAttribute, 0)
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
			-- everyone into their HQ's wave line; the first wave goes when the countdown ends
			phase("Countdown", Cfg.CountdownSeconds)
			local start = workspace:GetServerTimeNow() + Cfg.CountdownSeconds
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
			task.wait(Cfg.CountdownSeconds)
			release()
			setWave(Rules.nextWave(start, Cfg.Waves.every, workspace:GetServerTimeNow() + 0.05))
			phase("Playing")
			playedAt = os.clock()
		end
		local winner: Rules.Side? = nil
		local last = os.clock()
		still = 0
		while not winner and not ending do
			task.wait(Cfg.Tick)
			local dt = os.clock() - last
			last = os.clock()
			still += dt
			local rate = Rules.momentum(Cfg, still)
			folder:SetAttribute("Momentum", rate)
			if waveAt and workspace:GetServerTimeNow() >= (waveAt :: number) then
				release()
				setWave((waveAt :: number) + Cfg.Waves.every)
			end
			local w, e = heads()
			folder:SetAttribute(Cfg.ReinforcedAttribute, Rules.reinforced(Cfg.Reinforcements, w, e))
			local counts, inside = occupancy()
			latest = counts
			for _, ev in Rules.step(state, Cfg, counts, dt, rate) do
				if ev.kind == "Captured" then
					still = 0
					captured = true
					table.insert(log, { t = os.clock() - playedAt, index = ev.index, side = ev.side })
				else
					-- (a holder lost it: both sides' artillery goes up a level)
					lost += 1
					folder:SetAttribute(Cfg.LevelAttribute, Rules.gunLevel(Cfg.Artillery, lost))
				end
				local reason = if ev.kind == "Captured" then "Capture" else "Neutralise"
				for _, who in inside[ev.index] do
					local side = if isPlayer(who) then sideOf(who :: Player) else sideOfModel(who :: Model)
					if side == ev.side then
						award(who, reason)
					end
				end
			end
			publish(counts)
			winner = Rules.winner(state)
		end
		-- the results
		if winner then
			for _, p in Players:GetPlayers() do
				if Rules.sideOf(pair, Kits.next(p)) == winner then
					award(p, "Win")
				end
			end
			for _, m in bots() do
				if sideOfModel(m) == winner then
					award(m, "Win")
				end
			end
		end
		folder:SetAttribute("Winner", winner)
		release()
		setWave(nil)
		folder:SetAttribute(Cfg.ReinforcedAttribute, nil)
		phase("Results", Cfg.ResultsSeconds)
		MatchStats.send({
			mode = "Normal",
			winner = if winner then pair[winner] else nil,
			log = table.clone(log),
			length = os.clock() - playedAt,
			endsAt = folder:GetAttribute("PhaseEndsAt"),
		}, function(p: Player): string?
			return Kits.next(p)
		end)
		task.wait(Cfg.ResultsSeconds)
		newMatch(true)
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
function Frontline.running(): boolean
	return thread ~= nil
end

-- Starts the match (src/server/Modes, switching to Normal): false with Map 1 unbuilt.
function Frontline.start(): boolean
	if thread then
		return false
	end
	if not workspace:FindFirstChild(Cfg.MapKey) then
		warn(`[Frontline] the map isn't built: Greybox.build("{Cfg.MapKey}")`)
		return false
	end
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
	if thread then
		task.cancel(thread :: thread)
		newMatch(true)
		thread = task.spawn(run)
	end
end

-- Admin: the match starts now, without waiting for each side's players (a solo test)
function Frontline.begin()
	if thread and folder:GetAttribute("Phase") == "Waiting" then
		starting = true
	end
end

-- Admin: the match ends now with no winner (the results, then the next match).
function Frontline.finish()
	if thread then
		ending = true
	end
end

-- Admin: `player`'s side takes the sector it is attacking now (counts as a capture: the momentum starts over; no
-- points paid).
function Frontline.take(player: Player)
	local side = sideOf(player)
	local t = side and Rules.target(state, side)
	if not thread or folder:GetAttribute("Phase") ~= "Playing" or not side or not t then
		return
	end
	if state.owner[t] ~= "Neutral" then
		lost += 1
		folder:SetAttribute(Cfg.LevelAttribute, Rules.gunLevel(Cfg.Artillery, lost))
	end
	state.owner[t] = side
	state.control[t] = Rules.rest(side)
	still = 0
	captured = true
	table.insert(log, { t = os.clock() - playedAt, index = t, side = side })
end

return Frontline
