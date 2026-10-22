--!strict
-- Barbed wire on the soldiers (Config/Build.Wire; the pieces: src/server/Build). Every Wire.tick seconds each soldier
-- whose root stands in a finished wire's box is "Wired" (a character attribute: src/client/Stance slows them to
-- Wire.speed, no sprint, no jump) and loses health while moving through it (Rules/Build.wireHarm), both teams alike.

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
					local inside = false
					for _, w in wires do
						local l = w.frame:PointToObjectSpace(root.Position)
						if Rules.inBox(l.X, l.Y, l.Z, w.size.X, w.size.Y, w.size.Z) then
							inside = true
							break
						end
					end
					if (character:GetAttribute("Wired") == true) ~= inside then
						character:SetAttribute("Wired", if inside then true else nil)
					end
					if inside then
						local v = root.AssemblyLinearVelocity
						local harm = Rules.wireHarm(Vector3.new(v.X, 0, v.Z).Magnitude, C.Wire.tick, C.Wire)
						if harm > 0 then
							Damage.hurtBy(character, harm)
						end
					end
				end
			end
		end
	end)
end

return Wire
