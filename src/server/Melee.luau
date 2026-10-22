--!strict
-- A gun's butt stroke on the server (Config/Melee, Rules/Melee; src/client/Melee shows it). The client says when the
-- butt lands ("Melee", the direction it goes); this decides:
-- - a gun with ammo in the hands, alive, not ragdolled, its action idle (Rules/Firing.busy), the cooldown passed
--   (Config/Melee.Strike, with slack), the direction within the cone of where the soldier faces;
-- - the reach: every body part of a soldier (src/server/Damage.soldiers) in a box `reach` long and 2 x `radius` across
--   in front of the head (a box, not a sphere cast: a sphere cast misses whoever it starts inside, a soldier pressed
--   against you); the part nearest the strike's line wins, if the head has a clear line to it (no strikes through a
--   wall). A helmeted head loses its helmet (src/server/Helmets) and takes the "Helmet" numbers.
-- - then src/server/Damage.melee, and "Struck" to everyone (the swing sound). Until the gun is back in the hold
--   src/server/Firing takes no shot, bolt or reload.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Melee)
local F = require(Shared.Rules.Firing)
local FiringCfg = require(Shared.Config.Firing)
local DamageRules = require(Shared.Rules.Damage)
local Rules = require(Shared.Rules.Melee)
local Net = require(Shared.Net)
local Damage = require(script.Parent.Damage)
local Firing = require(script.Parent.Firing)
local Helmets = require(script.Parent.Helmets)
local Ragdoll = require(script.Parent.Ragdoll)

local Melee = {}

local last: { [Player]: number } = {}

-- the soldier `part` belongs to (a body part straight under its model), or nil
local function soldierOf(part: BasePart, soldiers: { [Instance]: boolean }): Model?
	local model = part.Parent
	return if model and soldiers[model] and DamageRules.zone(part.Name) then model :: Model else nil
end

-- The body part the strike meets: the nearest to its line of every soldier part in reach (not the striker's).
local function target(character: Model, origin: Vector3, direction: Vector3): BasePart?
	local soldiers: { [Instance]: boolean } = {}
	for _, s in Damage.soldiers() do
		if s ~= character then
			soldiers[s] = true
		end
	end
	local reach, radius = Cfg.Hit.reach, Cfg.Hit.radius
	local box = CFrame.lookAt(origin, origin + direction) * CFrame.new(0, 0, -reach / 2)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local best, bestOff = nil, math.huge
	for _, part in workspace:GetPartBoundsInBox(box, Vector3.new(radius * 2, radius * 2, reach), params) do
		local who = soldierOf(part, soldiers)
		if who then
			local rel = part.Position - origin
			local along = math.clamp(rel:Dot(direction), 0, reach)
			local off = (rel - direction * along).Magnitude
			if off < bestOff then
				best, bestOff = part, off
			end
		end
	end
	if not best then
		return nil
	end
	-- a clear line from the head to it (nothing but that soldier in the way)
	local ray = RaycastParams.new()
	ray.FilterType = Enum.RaycastFilterType.Exclude
	ray.FilterDescendantsInstances = { character, best.Parent :: Instance }
	if workspace:Raycast(origin, best.Position - origin, ray) then
		return nil
	end
	return best
end

local function strike(player: Player, direction: any)
	if typeof(direction) ~= "Vector3" or direction.Magnitude < 1e-3 or direction.Magnitude ~= direction.Magnitude then
		return
	end
	local now = os.clock()
	local character, tool, e = Firing.held(player)
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not tool or not e or not head or not root then
		return
	end
	local look = root.CFrame.LookVector
	local dir = direction.Unit
	if
		not Rules.ready(last[player], now, Cfg.Strike.cooldown, Cfg.Hit.slack)
		or not Rules.free({ busy = F.busy(e.state, now, FiringCfg.Slack), ragdolled = Ragdoll.active(character) })
		or not Rules.facing(dir.X, dir.Z, look.X, look.Z, Cfg.Hit.cone)
	then
		return
	end
	last[player] = now
	Firing.strike(character, now + Cfg.Strike.length - Cfg.Strike.impact)
	local origin = head.Position
	local part = target(character, origin, dir)
	if part then
		local zone = DamageRules.zone(part.Name) :: string
		local victim = part.Parent :: Model
		if zone == "Head" and victim:GetAttribute("HelmetOn") == true then
			Helmets.knockOff(victim, dir)
			zone = "Helmet"
		end
		Damage.melee(character, part, zone, dir)
	end
	Net.event("Struck"):FireAllClients(character)
end

function Melee.start()
	Net.event("Melee").OnServerEvent:Connect(strike)
	Players.PlayerRemoving:Connect(function(p)
		last[p] = nil
	end)
end

return Melee
