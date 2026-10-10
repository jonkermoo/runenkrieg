--!strict
-- Proves the runner works and Config is requirable outside Roblox.
local Config = require("../src/shared/Config")

return {
	["config loads as a frozen table"] = function()
		assert(table.isfrozen(Config), "Config must be frozen")
	end,
}
