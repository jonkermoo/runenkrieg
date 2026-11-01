--!strict
-- The knocks as each client shows them (Config/Ragdoll; M12: the server decides and loosens the joints for everyone,
-- src/server/Ragdoll). Net "Knock" (character, knock, direction, scale) comes to every client:
-- - the knocked body's own client (it owns the physics) throws it: the Humanoid goes to the Physics state (no walking,
--   jumping or standing) while the server's "Ragdolled" attribute is set, and gets up when the server clears it; a
--   limp body still upright a moment later is tipped over the way it was thrown (Config/Ragdoll.Tip).
-- "Ragdolled": the camera rides the head and the stance and weapon code take no input (src/client/WeaponCamera,
-- Stance, StaffAttack, Firing). Ragdoll.knockSelf(name, direction) asks the server to knock the local soldier (the
-- staff's recoil, the float fall: Net "KnockSelf") and throws it at once, before the joints come loose.
-- Down and alive, the stay-down key held or let go goes to the server (Net "StayDown", Config/Ragdoll.StayDown).
-- Getting up (the server's "GetUp", Config/Ragdoll.GetUp): the local soldier's root is stood upright where it will
-- stand and the get-up for how it lay plays (Rules/Ragdoll.getUpWay; src/client/Stance holds it still meanwhile).

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Ragdoll)
local Net = require(Shared.Net)
local RagdollRules = require(Shared.Rules.Ragdoll)

local Ragdoll = {}

local STAY = (Enum.KeyCode :: any)[Cfg.StayDown.key] :: Enum.KeyCode

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

-- the get-up animations, made once (each character's Animator loads its own tracks)
local GET_UP: { [string]: Animation } = {}
for way, g in Cfg.GetUp do
	if type(g) == "table" then
		local a = Instance.new("Animation")
		a.AnimationId = "rbxassetid://" .. g.id
		GET_UP[way] = a
	end
end

-- Stands the local `character` up by the get-up `way` ("Back" / "Front"): the root upright on the ground where it will
-- stand (Config/Ragdoll.GetUp `ahead` on from the lying torso, facing the way Rules/Ragdoll.getUpWay gives), then the
-- animation, which lies the torso down there and brings it up.
local function getUp(character: Model, humanoid: Humanoid, way: string, tracks: { [string]: AnimationTrack })
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local torso = character:FindFirstChild("Torso") :: BasePart?
	local g = (Cfg.GetUp :: any)[way]
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not root or not torso or not g or not animator or not GET_UP[way] then
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		return
	end
	local cf = torso.CFrame
	local _, fx, fz = RagdollRules.getUpWay(
		{ x = cf.LookVector.X, y = cf.LookVector.Y, z = cf.LookVector.Z },
		{ x = cf.UpVector.X, y = cf.UpVector.Y, z = cf.UpVector.Z }
	)
	local forward = Vector3.new(fx, 0, fz)
	local at = torso.Position + forward * g.ahead
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local S = Cfg.Stand
	local hit = workspace:Raycast(at + Vector3.yAxis * 2, Vector3.new(0, -(S.probe + 2), 0), params)
	local leg = character:FindFirstChild("Left Leg") :: BasePart?
	local height = (if leg then leg.Size.Y else 2) + root.Size.Y / 2 + humanoid.HipHeight
	local pos = Vector3.new(at.X, if hit then hit.Position.Y + height else torso.Position.Y + height - 0.5, at.Z)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = CFrame.lookAt(pos, pos + forward)
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	local track = tracks[way]
	if not track then
		track = animator:LoadAnimation(GET_UP[way])
		track.Priority = Enum.AnimationPriority.Action4
		track.Looped = false
		tracks[way] = track
	end
	track:Play(Cfg.GetUp.fade)
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
		local tracks: { [string]: AnimationTrack } = {} -- the get-ups, loaded on first use
		character:GetAttributeChangedSignal("Ragdolled"):Connect(function()
			if character:GetAttribute("Ragdolled") == true then
				asked[character] = nil -- the server's ragdoll is here
				for _, t in tracks do
					t:Stop(0) -- (knocked again while getting up)
				end
				if humanoid.Health > 0 then
					humanoid:ChangeState(Enum.HumanoidStateType.Physics)
					-- the key already held as the body went down counts too
					if UserInputService:IsKeyDown(STAY) then
						Net.event("StayDown"):FireServer(true)
					end
				end
			elseif humanoid.Health > 0 then
				local way = character:GetAttribute("GetUp")
				if type(way) == "string" then
					getUp(character, humanoid, way, tracks)
				else
					humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
				end
			end
		end)
		-- dragged by a teammate (src/server/Dragging holds the body's physics), and let go while still down: limp here too
		character:GetAttributeChangedSignal("Dragged"):Connect(function()
			if character:GetAttribute("Ragdolled") == true and humanoid.Health > 0 then
				humanoid:ChangeState(Enum.HumanoidStateType.Physics)
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
	-- the stay-down key, down and alive (not typing in a text box; let go always counts)
	local function stayDown(input: InputObject, typing: boolean)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if input.KeyCode ~= STAY or not character or character:GetAttribute("Ragdolled") ~= true then
			return
		end
		local holding = input.UserInputState == Enum.UserInputState.Begin
		if holding and (typing or not humanoid or humanoid.Health <= 0) then
			return
		end
		Net.event("StayDown"):FireServer(holding)
	end
	UserInputService.InputBegan:Connect(stayDown)
	UserInputService.InputEnded:Connect(stayDown)
	-- (loaded before the first knock, or the first get-up shows a frozen pose)
	task.spawn(function()
		local list = {}
		for _, a in GET_UP do
			table.insert(list, a)
		end
		pcall(ContentProvider.PreloadAsync, ContentProvider, list)
	end)
	player.CharacterAdded:Connect(watch)
	if player.Character then
		task.spawn(watch, player.Character)
	end
end

return Ragdoll
