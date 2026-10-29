--!strict
-- The frontline match, Normal mode (Config/Frontline, Rules/Frontline; user 2026-10-27: "a standard 5 stage territory
-- push between 2 sides") on Map 1's sector chain (Config/Maps/Map1.sectors: S1 the West HQ, S5 the East HQ).
-- src/server/Modes starts and stops it. Each match draws two teams (Workspace's MatchTeams attribute,
-- Rules/Frontline.pair), one on each side; a soldier's side is their team's (the character's "Kit"). A match waits
-- until each side has its players, counts down, then plays: every Tick the soldiers alive and on their feet in each
-- sector's zone push its control, faster the longer the front has stood still (momentum). Captures and
-- neutralisations pay each soldier of that side in the zone, a kill near your side's attacked sector pays a Defend,
-- and taking the enemy HQ wins (everyone on the winning side paid); then the results and a fresh match (sides reset, a
-- new pair, everyone respawns). Each life spawns in its side's spawn zone (Map1.spawnZones). The state is replicated as
-- attributes on Workspace's "Frontline" folder (Config/Frontline.FolderName, read by src/client/ModeHud). The sector
-- markers (src/dev/Greybox, shown by the admin's switch: src/server/Sectors) are coloured by owner and labelled with
-- control and head counts. The admin panel ends and restarts a match and takes a side's next sector
-- (src/server/DevTools).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Frontline)
local SectorCfg = require(Shared.Config.Sectors)
local U = require(Shared.Config.Uniforms)
local Map = require(Shared.Config.Maps.Map1)
local Rules = require(Shared.Rules.Frontline)
local Damage = require(script.Parent.Damage)
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
local matchWatchers: { () -> () } = {}
-- while running: the match loop, the player hooks; set by the admin to end the match now
local thread: thread? = nil
local conns: { RBXScriptConnection } = {}
local ending = false
local still = 0 -- seconds since the last capture (the momentum)

-- `fn(player, reason)` for each award (a Config/Classes.Earn key: Capture, Neutralise, Defend, Win); `fn()` at each
-- match's start
function Frontline.onAward(fn: (Player, string) -> ())
	table.insert(awardWatchers, fn)
end
function Frontline.onMatchStart(fn: () -> ())
	table.insert(matchWatchers, fn)
end

local function award(player: Player, reason: string)
	for _, fn in awardWatchers do
		task.spawn(fn, player, reason)
	end
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

local function spawnAt(player: Player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local side = sideOf(player)
	if not character or not root or not side then
		return
	end
	local r = Map.spawnZones[side]
	local x = r.minX + (r.maxX - r.minX) * math.random()
	local z = r.minZ + (r.maxZ - r.minZ) * math.random()
	local pos = Vector3.new(x, ground(x, z) + Cfg.SpawnLift, z)
	local front = sectors[Rules.target(state, side) or 1]
	character:PivotTo(CFrame.lookAt(pos, Vector3.new(front.x, pos.Y, front.z)))
	root.AssemblyLinearVelocity = Vector3.zero
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
	local root = workspace:FindFirstChild(Map.name)
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
	showMarkers(counts)
end

local function empty(): { { West: number, East: number } }
	local counts = {}
	for i in sectors do
		counts[i] = { West = 0, East = 0 }
	end
	return counts
end

-- each sector's soldiers in its zone by side, and the players in each zone
local function occupancy(): ({ { West: number, East: number } }, { { Player } })
	local counts, inside = empty(), {}
	for i in sectors do
		inside[i] = {}
	end
	for _, p in Players:GetPlayers() do
		local root = alive(p)
		local side = sideOf(p)
		local character = p.Character
		if root and side and character and not Ragdoll.active(character) and not Damage.protected(character) then
			local feet = root.Position - Vector3.new(0, Cfg.FeetBelowRoot, 0)
			for i, s in sectors do
				if Rules.inZone(feet.X - s.x, feet.Z - s.z, feet.Y - zoneY[i], s.radius, Cfg.Height) then
					counts[i][side] += 1
					table.insert(inside[i], p)
					break
				end
			end
		end
	end
	return counts, inside
end

-- how many players each side has (by their next life's team)
local function heads(): (number, number)
	local w, e = 0, 0
	for _, p in Players:GetPlayers() do
		local side = Rules.sideOf(pair, Kits.next(p))
		if side == "West" then
			w += 1
		elseif side == "East" then
			e += 1
		end
	end
	return w, e
end

local function newMatch()
	pair = Rules.pair(U.Teams, math.random(), math.random())
	workspace:SetAttribute(Cfg.TeamsAttribute, Rules.pairText(pair))
	state = Rules.new(sectors)
	ending = false
	folder:SetAttribute("West", pair.West)
	folder:SetAttribute("East", pair.East)
	folder:SetAttribute("Winner", nil)
	folder:SetAttribute("Momentum", 1)
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
			local w, e = heads()
			if Rules.ready(w, e, Cfg.MinPerSide) then
				break
			end
			task.wait(Cfg.Tick)
		end
		if not ending then
			phase("Countdown", Cfg.CountdownSeconds)
			task.wait(Cfg.CountdownSeconds)
			phase("Playing")
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
			local counts, inside = occupancy()
			for _, ev in Rules.step(state, Cfg, counts, dt, rate) do
				if ev.kind == "Captured" then
					still = 0
				end
				local reason = if ev.kind == "Captured" then "Capture" else "Neutralise"
				for _, p in inside[ev.index] do
					if sideOf(p) == ev.side then
						award(p, reason)
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
		end
		folder:SetAttribute("Winner", winner)
		phase("Results", Cfg.ResultsSeconds)
		task.wait(Cfg.ResultsSeconds)
		newMatch()
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

-- Whether the match is running (the server's mode is Normal).
function Frontline.running(): boolean
	return thread ~= nil
end

-- Starts the match (src/server/Modes, switching to Normal): false with Map 1 unbuilt.
function Frontline.start(): boolean
	if thread then
		return false
	end
	if not workspace:FindFirstChild(Map.name) then
		warn(`[Frontline] the map isn't built: Greybox.build("Map1")`)
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
		newMatch()
		thread = task.spawn(run)
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
	state.owner[t] = side
	state.control[t] = Rules.rest(side)
	still = 0
end

return Frontline
