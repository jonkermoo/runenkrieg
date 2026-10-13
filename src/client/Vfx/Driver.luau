--!strict
-- One frame loop for every running effect (Config/Vfx.Quality): an effect adds a step function; each frame the step
-- gets (now, dt) and returns false when the effect is done. The loop disconnects itself when nothing runs.

local RunService = game:GetService("RunService")

local Driver = {}

type Step = (now: number, dt: number) -> boolean

local steps: { Step } = {}
local conn: RBXScriptConnection? = nil

local function frame(dt: number)
	local now = os.clock()
	local i = 1
	while i <= #steps do
		local ok, more = pcall(steps[i], now, dt)
		if ok and more then
			i += 1
		else
			if not ok then
				warn("Vfx step failed: " .. tostring(more))
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

function Driver.add(step: Step)
	table.insert(steps, step)
	if not conn then
		conn = RunService.RenderStepped:Connect(frame)
	end
end

-- How many effects are running (for the budgets in Config/Vfx.Quality).
function Driver.count(): number
	return #steps
end

return Driver
