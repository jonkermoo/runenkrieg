--!strict
-- The clock and the weather (Config/Environment, Rules/Environment), the same for every player: the server writes
-- when the day started and the current weather event (its kind and the server times it fades in from and out by) as
-- Workspace attributes; each client draws the light, haze and rain from them (src/client/Environment). The server
-- never writes Lighting itself: a replicated ClockTime would jerk every client's own smooth one.
-- Dev (Studio command bar in play, and the admin panel's Time rows through src/server/DevTools): `setClock(hours)`,
-- `pause(on)`, `force(kind, seconds?)`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Environment)
local Rules = require(Shared.Rules.Environment)

local A = Cfg.Attributes
local W = Cfg.Weather

local Environment = {}

local rng = Random.new()
local turn = 0 -- bumped by `force` so the running roll waits out the forced event instead

local function now(): number
	return workspace:GetServerTimeNow()
end

local function set(kind: string, from: number, to: number)
	workspace:SetAttribute(A.weather, kind)
	workspace:SetAttribute(A.from, from)
	workspace:SetAttribute(A.to, to)
end

local function pausedAt(): number?
	local p = workspace:GetAttribute(A.paused)
	return if typeof(p) == "number" then p else nil
end

-- Sets the clock now to `hours` (it keeps running from there, or stays there while paused).
function Environment.setClock(hours: number)
	workspace:SetAttribute(A.dayStart, Rules.startFor(hours, pausedAt() or now(), Cfg.Day))
end

-- Stops the clock where it is (`on`) or lets it run on from there.
function Environment.pause(on: boolean)
	local p = pausedAt()
	if on and not p then
		workspace:SetAttribute(A.paused, now())
	elseif not on and p then
		local start = workspace:GetAttribute(A.dayStart)
		if typeof(start) == "number" then
			workspace:SetAttribute(A.dayStart, start + now() - p)
		end
		workspace:SetAttribute(A.paused, nil)
	end
end

-- Starts `kind` ("Fog", "Rain", "Clear") now for `seconds` (a rolled length if nil); the rolls carry on after it.
function Environment.force(kind: string, seconds: number?)
	turn += 1
	local t = now()
	set(kind, t, t + (seconds or Rules.span(rng:NextNumber(), W.duration)))
end

local function roll()
	while true do
		local mine = turn
		local t = now()
		local to = workspace:GetAttribute(A.to)
		local wait = if typeof(to) == "number" and to > t then to - t else 0
		task.wait(wait + Rules.span(rng:NextNumber(), W.clear))
		if turn == mine then
			local kind = Rules.pick(rng:NextNumber(), W.odds)
			if kind ~= "Clear" then
				local from = now()
				set(kind, from, from + Rules.span(rng:NextNumber(), W.duration))
			end
		end
	end
end

function Environment.start()
	Environment.setClock(Cfg.Day.startClock)
	set("Clear", 0, 0)
	task.spawn(roll)
end

return Environment
