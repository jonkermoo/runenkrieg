--!strict
-- Hitch timings (the admin panel's Hitches rows; Config/DevTools.Admin.Hitches): the one-off jobs a player can feel as
-- a hitch, timed by name on the server and on each client. `Hitches.since(name, t0)` after the job (t0 = os.clock()
-- before it). With the log on (the Workspace attribute), one over `over` ms prints at once; `Hitches.report` is each
-- name's count, average, most and how many went over since the last report. `Hitches.watch` (server and every client,
-- once) also prints each whole frame over `frame` ms while the log is on, with what the engine spent it on (Stats) and
-- the jobs timed in it: a stall no job explains is the engine's (terrain, physics, drawing).

local RunService = game:GetService("RunService")

local Cfg = require(script.Parent.Config.DevTools).Admin.Hitches

local Hitches = {}

local SIDE = if RunService:IsServer() then "server" else "client"

type Stat = { n: number, sum: number, max: number, over: number }
local stats: { [string]: Stat } = {}
-- the jobs over `over` ms since the last frame (Hitches.watch)
local recent: { string } = {}

-- `ms` counted under `name`; whether it went over `over`
local function count(name: string, ms: number): boolean
	local s = stats[name]
	if not s then
		s = { n = 0, sum = 0, max = 0, over = 0 }
		stats[name] = s
	end
	s.n += 1
	s.sum += ms
	s.max = math.max(s.max, ms)
	if ms > Cfg.over then
		s.over += 1
	end
	return ms > Cfg.over
end

function Hitches.since(name: string, t0: number)
	local ms = (os.clock() - t0) * 1000
	if count(name, ms) then
		if workspace:GetAttribute(Cfg.attribute) == true then
			print(string.format("[Hitch] %s %s %.2f ms", SIDE, name, ms))
			table.insert(recent, string.format("%s %.1f", name, ms))
		end
	end
end

-- one line per name since the last report (then counted afresh)
function Hitches.report(): string
	local names = {}
	for name in stats do
		table.insert(names, name)
	end
	table.sort(names)
	local lines = { `[Hitches] {SIDE}: over {Cfg.over} ms` }
	for _, name in names do
		local s = stats[name]
		table.insert(
			lines,
			string.format("  %s: %d, avg %.2f ms, most %.2f ms, %d over", name, s.n, s.sum / s.n, s.max, s.over)
		)
	end
	if #names == 0 then
		table.insert(lines, "  (nothing timed yet)")
	end
	table.clear(stats)
	return table.concat(lines, "\n")
end

-- the frame watch (call once on each side)
function Hitches.watch()
	local Stats = game:GetService("Stats")
	local function read(name: string): number
		local ok, v = pcall(function()
			return (Stats :: any)[name]
		end)
		return if ok and type(v) == "number" then v else 0
	end
	local last = os.clock()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local ms = (now - last) * 1000
		last = now
		if ms > Cfg.frame and workspace:GetAttribute(Cfg.attribute) == true then
			count(`Frame over {Cfg.frame} ms`, ms)
			print(
				string.format(
					"[Hitch] %s frame %.0f ms: render cpu %.0f, gpu %.0f, physics %.1f, heartbeat %.1f ms; %d moving, %d instances; jobs: %s",
					SIDE,
					ms,
					read("RenderCPUFrameTime") * 1000,
					read("RenderGPUFrameTime") * 1000,
					read("PhysicsStepTimeMs"),
					read("HeartbeatTimeMs"),
					read("MovingPrimitivesCount"),
					read("InstanceCount"),
					if #recent > 0 then table.concat(recent, ", ") else "none"
				)
			)
		end
		table.clear(recent)
	end)
end

return Hitches
