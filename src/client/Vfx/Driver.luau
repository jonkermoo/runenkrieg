--!strict
-- One frame loop for every running effect (Config/Vfx.Quality): an effect adds a step function; each frame the step
-- gets (now, dt) and returns false when the effect is done. The loop disconnects itself when nothing runs. A step that
-- errors is dropped; its `cleanup` (if given) then gives its pieces back, so a failed effect can't leave a light or a
-- glowing part behind.

local RunService = game:GetService("RunService")

local Driver = {}

type Step = (now: number, dt: number) -> boolean

local steps: { Step } = {}
local cleanups: { [Step]: () -> () } = {}
local conn: RBXScriptConnection? = nil

local function frame(dt: number)
	local now = os.clock()
	local i = 1
	while i <= #steps do
		local ok, more = pcall(steps[i], now, dt)
		if ok and more then
			i += 1
		else
			local step = steps[i]
			local cleanup = cleanups[step]
			cleanups[step] = nil
			if not ok then
				warn("Vfx step failed: " .. tostring(more))
				if cleanup then
					local cleaned, why = pcall(cleanup)
					if not cleaned then
						warn("Vfx cleanup failed: " .. tostring(why))
					end
				end
			end
			steps[i] = steps[#steps] -- swap-remove
			steps[#steps] = nil
		end
	end
	if #steps == 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

function Driver.add(step: Step, cleanup: (() -> ())?)
	table.insert(steps, step)
	if cleanup then
		cleanups[step] = cleanup
	end
	if not conn then
		conn = RunService.RenderStepped:Connect(frame)
	end
end

-- How many effects are running (for the budgets in Config/Vfx.Quality).
function Driver.count(): number
	return #steps
end

return Driver
