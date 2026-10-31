--!strict
-- The knocks as each client shows them (Config/Ragdoll; M12: the server decides and loosens the joints for everyone,
-- src/server/Ragdoll). Net "Knock" (character, knock, direction, scale) comes to every client:
-- - the knocked body's own client (it owns the physics) throws it: the Humanoid goes to the Physics state (no walking,
--   jumping or standing) while the server's "Ragdolled" attribute is set, and gets up when the server clears it; a
--   limp body still upright a moment later is tipped over the way it was thrown (Config/Ragdoll.Tip).
-- "Ragdolled": the camera rides the head and the stance and weapon code take no input (src/client/WeaponCamera,
-- Stance, StaffAttack, Firing). Ragdoll.knockSelf(name, direction) asks the server to knock the local soldier (the
-- staff's recoil, the float fall: Net "KnockSelf") and throws it at once, before the joints come loose.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Ragdoll)
local Net = require(Shared.Net)

local Ragdoll = {}

-- the local soldier knocked by itself, waiting for the server's ragdoll (until this time)
local asked: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

function Ragdoll.active(character: Model): boolean
	return character:GetAttribute("Ragdolled") == true or (asked[character] or 0) > os.clock()
end

-- throws the local body: `knock` a Config/Ragdoll.Knocks entry along `direction` (flat; it tumbles that way)
local function throw(character: Model, knock: { [string]: number }, direction: Vector3, scale: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	local dir = if flat.Magnitude > 1e-3 then flat.Unit else -root.CFrame.LookVector
	if humanoid.Health > 0 then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end
	local velocity = (dir * knock.push + Vector3.yAxis * (knock.lift - (knock.drop or 0))) * scale
	-- tumble the way it's thrown: about the horizontal axis across the push
	local axis = Vector3.new(0, 1, 0):Cross(dir)
	-- held for Tip.hold s, as src/server/Ragdoll does for a dead body (Studio, staff round 1: set once, a living
	-- body going limp lost most of it, so every blast throw came out alike)
	local spin = axis * knock.tumble * scale
	task.spawn(function()
		local stopAt = os.clock() + Cfg.Tip.hold
		repeat
			root.AssemblyLinearVelocity = velocity
			root.AssemblyAngularVelocity = spin
			task.wait()
		until os.clock() >= stopAt or not root.Parent
	end)
	-- nobody ragdolls standing up: still upright a moment later, it's tipped over the way it was thrown
	local torso = character:FindFirstChild("Torso") :: BasePart?
	-- (every `every` s for `window` s, while this client still simulates the body: ReceiveAge 0)
	local T = Cfg.Tip
	task.spawn(function()
		local t0 = os.clock()
		task.wait(T.after)
		while torso and torso.Parent and Ragdoll.active(character) and os.clock() - t0 < T.window do
			if torso.ReceiveAge == 0 and torso.CFrame.UpVector.Y > T.upright then
				torso.AssemblyAngularVelocity += axis * T.spin
				torso.AssemblyLinearVelocity += dir * T.push
			end
			task.wait(T.every)
		end
	end)
end

-- Knocks the local soldier with the Config/Ragdoll.SelfKnocks entry `name`: thrown now, the server loosens the joints.
function Ragdoll.knockSelf(name: string, direction: Vector3)
	local character = Players.LocalPlayer.Character
	local knock = Cfg.Knocks[name]
	if not character or not knock or Ragdoll.active(character) then
		return
	end
	asked[character] = os.clock() + Cfg.SelfWait
	throw(character, knock, direction, 1)
	Net.event("KnockSelf"):FireServer(name, direction)
end

function Ragdoll.start()
	local player = Players.LocalPlayer
	Net.event("Knock").OnClientEvent:Connect(function(character: Model, name: string, direction: Vector3, scale: number)
		local knock = Cfg.Knocks[name]
		if typeof(character) ~= "Instance" or not knock then
			return
		end
		if character == player.Character and not asked[character] then
			throw(character, knock, direction, scale)
		end
	end)
	-- the local soldier: held in the Physics state while ragdolled, up again when the server clears it
	local function watch(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
		if not humanoid then
			return
		end
		character:GetAttributeChangedSignal("Ragdolled"):Connect(function()
			if character:GetAttribute("Ragdolled") == true then
				asked[character] = nil -- the server's ragdoll is here
				if humanoid.Health > 0 then
					humanoid:ChangeState(Enum.HumanoidStateType.Physics)
				end
			elseif humanoid.Health > 0 then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)
		-- dragged by a teammate (src/server/Dragging holds the body's physics), and let go while still down: limp here too
		character:GetAttributeChangedSignal("Dragged"):Connect(function()
			if character:GetAttribute("Ragdolled") == true and humanoid.Health > 0 then
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end
		end)
		-- (DIAG staff self-kill, user 2026-10-31: how the local soldier dies, as this client sees it)
		humanoid.StateChanged:Connect(function(old, new)
			if new == Enum.HumanoidStateType.Dead or old == Enum.HumanoidStateType.Physics then
				local torso = character:FindFirstChild("Torso")
				local neck = torso and torso:FindFirstChild("Neck") :: Motor6D?
				local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local at = if root then tostring(root.Position) else "no root"
				local neckOn = if neck then tostring(neck.Enabled) else "missing"
				warn(
					`[Ragdoll] DIAG local {old.Name} -> {new.Name}: health {humanoid.Health}, neck {neckOn}, at {at}, ragdolled {character:GetAttribute(
						"Ragdolled"
					)}`
				)
			end
		end)
		-- a knock asked for that the server never answered: up again
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Physics and asked[character] then
				local stopAt = asked[character]
				task.delay(Cfg.SelfWait, function()
					if asked[character] == stopAt and character:GetAttribute("Ragdolled") ~= true then
						asked[character] = nil
						if humanoid.Health > 0 then
							humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
						end
					end
				end)
			end
		end)
	end
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

return Ragdoll
