--!strict
-- Hitch timings (the admin panel's Hitches rows; Config/DevTools.Admin.Hitches): the one-off jobs a player can feel as
-- a hitch, timed by name on the server and on each client. `Hitches.since(name, t0)` after the job (t0 = os.clock()
-- before it). With the log on (the Workspace attribute), one over `over` ms prints at once; `Hitches.report` is each
-- name's count, average, most and how many went over since the last report.

local RunService = game:GetService("RunService")

local Cfg = require(script.Parent.Config.DevTools).Admin.Hitches

local Hitches = {}

local SIDE = if RunService:IsServer() then "server" else "client"

type Stat = { n: number, sum: number, max: number, over: number }
local stats: { [string]: Stat } = {}

function Hitches.since(name: string, t0: number)
	local ms = (os.clock() - t0) * 1000
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
		if workspace:GetAttribute(Cfg.attribute) == true then
			print(string.format("[Hitch] %s %s %.2f ms", SIDE, name, ms))
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

return Hitches
