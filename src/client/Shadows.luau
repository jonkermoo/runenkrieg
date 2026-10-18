--!strict
-- The player's Shadows setting (src/client/Settings): Lighting.GlobalShadows on this client only.

local Lighting = game:GetService("Lighting")

local Settings = require(script.Parent.Settings)

local Shadows = {}

function Shadows.start()
	local function apply(v: string)
		Lighting.GlobalShadows = v == "On"
	end
	apply(Settings.get("Shadows"))
	Settings.changed("Shadows", apply)
end

return Shadows
