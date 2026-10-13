--!strict
-- Shooting on the server (M11; Config/Firing, Rules/Firing). Each weapon Tool carries its action's state (rounds in
-- the magazine, a round or a spent case in the chamber), published as Tool attributes ("Magazine", "Chambered",
-- "Spent") for every client's ammo display and effects. The client predicts; this decides:
-- - Fire(origin, direction): the shooter's held rifle must have a live round chambered and be idle (Rules/Firing,
--   with Config/Firing.Slack for latency); the muzzle must be near the shooter's head and in sight of it; then the
--   ray is cast here (hitscan, Config/Firing.Range, the shooter excluded) and the shot goes out to everyone ("Shot").
--   No damage yet (user 2026-10-12: damage physics comes later).
-- - WorkBolt / Reload / StopLoad: the same state machine; accepted actions go out to everyone ("WeaponAction") so the
--   parts move and the sounds play for all. A Reload with rounds left in a stripper-clip rifle loads single rounds
--   ("Load"); StopLoad ends it after the round in the hand ("LoadStop"); when it has ended its rounds are settled into
--   the magazine and published.
-- Every remote is rate limited per player (Config/Firing.RatePerSecond). A new Tool (each spawn) starts full.
-- "Seq" counts the requests answered for the Tool (accepted or not), so the client knows when its own predictions are
-- all in and the attributes are the whole truth. "Open": the bolt is held open on the empty rifle.
-- Put away mid-action (the Tool goes to the Backpack), the action's time left is kept; drawn again it plays out after
-- Config/Firing.Resume.delay (Rules/Firing pause / resume), and everyone is told to show the rest of it
-- ("WeaponAction" with the span still to play and the delay).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Firing)
local W = require(Shared.Config.Weapons)
local F = require(Shared.Rules.Firing)
local Net = require(Shared.Net)

local Firing = {}

-- the action under way: its name, what it threw out, the share of its timeline it plays (from, to; Config/Firing
-- BoltCycle / ReloadCycle) and when that span ends
type Last = { action: string, out: string?, from: number, to: number, ends: number, span: number }
type Entry = { state: F.State, gun: F.Gun, seq: number, last: Last? }
local states: { [Tool]: Entry } = setmetatable({}, { __mode = "k" }) :: any

function Firing.gun(name: string): F.Gun
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

local function publish(tool: Tool, s: F.State, seq: number?)
	F.settle(s, os.clock())
	tool:SetAttribute("Magazine", s.magazine)
	tool:SetAttribute("Chambered", s.chambered)
	tool:SetAttribute("Spent", s.spent)
	tool:SetAttribute("Open", s.open)
	if seq then
		tool:SetAttribute("Seq", seq)
	end
end

-- publish a single load's rounds once it has ended (each start, stop or resume moves the end)
local function settleLater(tool: Tool, s: F.State)
	local l = s.load
	if not l then
		return
	end
	task.delay(math.max(0, s.busyUntil - os.clock()) + 0.05, function()
		if s.load == l and not l.elapsed and os.clock() >= s.busyUntil then
			publish(tool, s)
		end
	end)
end

-- The weapon's state (a full rifle the first time it's seen).
function Firing.entry(tool: Tool): Entry?
	local name = tool:GetAttribute("Weapon")
	if type(name) ~= "string" or not W[name] then
		return nil
	end
	local e = states[tool]
	if not e then
		local gun = Firing.gun(name)
		local made: Entry = { state = F.new(gun), gun = gun, seq = 0, last = nil }
		e = made
		states[tool] = made
		publish(tool, made.state)
		-- put away / drawn again: the action under way pauses, then plays out after the draw
		tool:GetPropertyChangedSignal("Parent"):Connect(function()
			local parent = tool.Parent
			local now = os.clock()
			if parent and parent:IsA("Backpack") then
				F.pause(made.state, now)
			elseif parent and parent:FindFirstChildOfClass("Humanoid") then
				local left = F.resume(made.state, now, Cfg.Resume.delay)
				local last = made.last
				local l = made.state.load
				if left > 0 and l and last and last.action == "Load" then
					-- single rounds: carry on where it stopped (seconds into it), the round in the hand included
					local from = now + Cfg.Resume.delay - l.start
					local out = if from < 0.8 * l.open then last.out else nil
					Net.event("WeaponAction"):FireAllClients(parent, "Load", out, from, l.rounds, Cfg.Resume.delay)
					settleLater(tool, made.state)
				elseif left > 0 and last and last.span > 0 then
					-- where in its span the action stopped
					local done = math.clamp(1 - left / last.span, 0, 1)
					local from = last.from + (last.to - last.from) * done
					local ejectAt = if last.action == "Bolt" then Cfg.BoltCycle.back else Cfg.ReloadCycle.back
					local out = if from < ejectAt then last.out else nil -- the case may already be out
					Net.event("WeaponAction"):FireAllClients(parent, last.action, out, from, last.to, Cfg.Resume.delay)
				end
			end
		end)
	end
	return e
end

-- The weapon the player has in the hands, if alive.
local function held(player: Player): (Model?, Tool?, Entry?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return nil, nil, nil
	end
	local tool = character:FindFirstChildOfClass("Tool")
	local e = tool and Firing.entry(tool)
	return character, tool, e
end

-- a token bucket per player: RatePerSecond refill, the same burst
local buckets: { [Player]: { tokens: number, at: number } } = {}
local function allowed(player: Player): boolean
	local now = os.clock()
	local b = buckets[player]
	if not b then
		b = { tokens = Cfg.RatePerSecond, at = now }
		buckets[player] = b
	end
	b.tokens = math.min(Cfg.RatePerSecond, b.tokens + (now - b.at) * Cfg.RatePerSecond)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function shoot(player: Player, origin: any, direction: any)
	local character, tool, e = held(player)
	local head = character and character:FindFirstChild("Head") :: BasePart?
	if not character or not tool or not e or not head then
		return
	end
	e.seq += 1
	local ok = typeof(origin) == "Vector3"
		and typeof(direction) == "Vector3"
		and allowed(player)
		and F.validShot((origin - head.Position).Magnitude, direction.Magnitude, Cfg.MaxOrigin)
	if not ok or not F.fire(e.state, e.gun, os.clock(), Cfg.Slack) then
		publish(tool, e.state, e.seq) -- the client resyncs to this
		return
	end
	publish(tool, e.state, e.seq)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	-- the muzzle must be in sight of the head (no shooting from a barrel pushed through a wall)
	local start = workspace:Raycast(head.Position, origin - head.Position, params)
	local result = start or workspace:Raycast(origin, direction * Cfg.Range, params)
	local hit = if result then result.Position else origin + direction * Cfg.Range
	Net.event("Shot"):FireAllClients(
		character,
		tool:GetAttribute("Weapon"),
		origin,
		hit,
		result and result.Normal,
		result and result.Instance
	)
end

local function act(player: Player, action: string)
	local character, tool, e = held(player)
	if not character or not tool or not e then
		return
	end
	e.seq += 1
	local ok, _, out, kind = false, nil, nil, nil
	local now = os.clock()
	local wasOpen = e.state.open
	if not allowed(player) then
		ok = false
	elseif action == "Bolt" then
		ok, _, out = F.bolt(e.state, e.gun, now, Cfg.Slack)
	elseif action == "StopLoad" then
		local k = F.stopLoad(e.state, now)
		publish(tool, e.state, e.seq)
		if k then
			Net.event("WeaponAction"):FireAllClients(character, "LoadStop", nil, nil, k, nil)
			settleLater(tool, e.state)
		end
		return
	else
		ok, _, out, kind = F.reload(e.state, e.gun, now, Cfg.Slack)
	end
	publish(tool, e.state, e.seq)
	if ok and kind == "Load" then
		e.last = { action = "Load", out = out, from = 0, to = 1, ends = e.state.busyUntil, span = 0 }
		Net.event("WeaponAction"):FireAllClients(character, "Load", out, 0, nil, nil)
		settleLater(tool, e.state)
	elseif ok then
		-- the span of the timeline this action plays: a bolt opening on an empty rifle stops when it's back; a reload
		-- from an open bolt starts there
		local from = if action == "Reload" and wasOpen then Cfg.ReloadCycle.back else 0
		local to = if action == "Bolt" and e.state.open then Cfg.BoltCycle.back else 1
		e.last = {
			action = action,
			out = out,
			from = from,
			to = to,
			ends = e.state.busyUntil,
			span = e.state.busyUntil - now,
		}
		Net.event("WeaponAction"):FireAllClients(character, action, out, from, to, nil)
	end
end

function Firing.start()
	Net.event("Fire").OnServerEvent:Connect(shoot)
	Net.event("WorkBolt").OnServerEvent:Connect(function(player)
		act(player, "Bolt")
	end)
	Net.event("Reload").OnServerEvent:Connect(function(player)
		act(player, "Reload")
	end)
	Net.event("StopLoad").OnServerEvent:Connect(function(player)
		act(player, "StopLoad")
	end)
	-- publish a new weapon's rounds as soon as it is given (the ammo display shows them before the first shot)
	local function watch(player: Player)
		local function tool(child: Instance)
			if child:IsA("Tool") then
				Firing.entry(child)
			end
		end
		local function backpack(b: Instance)
			if b:IsA("Backpack") then
				b.ChildAdded:Connect(tool)
				for _, c in b:GetChildren() do
					tool(c)
				end
			end
		end
		player.ChildAdded:Connect(backpack)
		for _, c in player:GetChildren() do
			backpack(c)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		buckets[p] = nil
	end)
end

return Firing
