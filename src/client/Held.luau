--!strict
-- What the local soldier holds: the equipped weapon Tool (Config/Weapons name in its "Weapon" attribute) and its
-- "Hold" Motor6D, which joins the gun to the Torso (src/server/Armory).

local Held = {}

export type Weapon = { tool: Tool, name: string, hold: Motor6D, gun: BasePart }

function Held.weapon(character: Model?): Weapon?
	local tool = character and character:FindFirstChildOfClass("Tool")
	local name = tool and tool:GetAttribute("Weapon")
	if not tool or type(name) ~= "string" then
		return nil
	end
	local hold = tool:FindFirstChild("Hold", true) :: Motor6D?
	local gun = hold and hold.Part1
	if not hold or not gun then
		return nil
	end
	return { tool = tool, name = name, hold = hold, gun = gun }
end

return Held
