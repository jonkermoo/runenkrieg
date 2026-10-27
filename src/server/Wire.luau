--!strict
-- Barbed wire on the soldiers (Config/Build.Wire; the pieces: src/server/Build). Every Wire.tick seconds each soldier
-- whose root stands in a standing wire's box is "Wired" (a character attribute: src/client/Stance slows them to
-- Wire.speed, no sprint, no jump), both teams alike; the enemy loses health while moving through it (Rules/Build.wireHarm),
-- and each tick anyone moves through it (Rules/Build.wireRattles) the wire's "RattleFrom" (where) and "ShakeAt" (when)
-- are set: src/client/WireShake shakes it and plays its rattle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Build)
local Rules = require(Shared.Rules.Build)
local Build = require(script.Parent.Build)
local Damage = require(script.Parent.Damage)

local Wire = {}

function Wire.start()
	task.spawn(function()
		while true do
			task.wait(C.Wire.tick)
			local wires = Build.wires()
			for _, character in Damage.soldiers() do
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then
					local inside: Build.WireBox? = nil
					for _, w in wires do
						local l = w.frame:PointToObjectSpace(root.Position)
						if Rules.inBox(l.X, l.Y, l.Z, w.size.X, w.size.Y, w.size.Z) then
							inside = w
							break
						end
					end
					if (character:GetAttribute("Wired") == true) ~= (inside ~= nil) then
						character:SetAttribute("Wired", if inside then true else nil)
					end
					if inside then
						local v = root.AssemblyLinearVelocity
						local speed = Vector3.new(v.X, 0, v.Z).Magnitude
						local friend = character:GetAttribute("Kit") == inside.team
						local harm = Rules.wireHarm(speed, C.Wire.tick, C.Wire, friend)
						if harm > 0 then
							Damage.hurtBy(character, harm)
						end
						if Rules.wireRattles(speed, C.Wire) then
							inside.model:SetAttribute("RattleFrom", root.Position)
							inside.model:SetAttribute("ShakeAt", workspace:GetServerTimeNow())
						end
					end
				end
			end
		end
	end)
end

return Wire
