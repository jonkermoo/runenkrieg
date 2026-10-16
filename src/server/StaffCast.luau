--!strict
-- Relays each caster's staff cast (src/client/StaffAttack) to the other players, who draw and hear it
-- (src/client/StaffSeen). Visual and audio only: nothing here hits or hurts. Nothing a client sends is trusted as
-- sent (Rules/StaffNet, Config/Spells.Send): the sender must be alive with a staff in the hands; every message type and
-- value is checked; points must be near the caster's head; "Aim" goes at most AimRate a second, everything else
-- through a token bucket of Events a second; a "Fire" must wait out the last shot's cooldown (less CooldownSlack).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Spells = require(Shared.Config.Spells)
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.StaffNet)

local Send = Spells.Send
local LAST = #Spells.Stages

local StaffCast = {}

type State = { bucket: Rules.Bucket, aimAt: number, fireAt: number?, fireStage: number?, staffAt: number }

-- the sender's character and head, alive; and whether a staff is drawn
local function caster(player: Player): (Model?, BasePart?, boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head") :: BasePart?
	local tool = character and character:FindFirstChildOfClass("Tool")
	local name = tool and tool:GetAttribute("Weapon")
	if not character or not humanoid or humanoid.Health <= 0 or not head then
		return nil, nil, false
	end
	local w = type(name) == "string" and W[name]
	return character, head, w ~= nil and w ~= false and w.class == "Staff"
end

-- a point near the caster's head, or nil
local function point(v: unknown, head: BasePart): Vector3?
	if typeof(v) ~= "Vector3" then
		return nil
	end
	local p = v :: Vector3
	if not (Rules.finite(p.X) and Rules.finite(p.Y) and Rules.finite(p.Z)) then
		return nil
	end
	return if (p - head.Position).Magnitude <= Send.Reach then p else nil
end

function StaffCast.start()
	local remote = Net.event("StaffCast")
	local states: { [Player]: State } = {}

	local function relay(from: Player, character: Model, ...: any)
		for _, other in Players:GetPlayers() do
			if other ~= from then
				remote:FireClient(other, character, ...)
			end
		end
	end

	remote.OnServerEvent:Connect(function(player, kind, a, b, c)
		local character, head, staff = caster(player)
		if not character or not head or type(kind) ~= "string" then
			return
		end
		local now = os.clock()
		local s = states[player]
		if not s then
			s = {
				bucket = { tokens = Send.Events, at = now },
				aimAt = -math.huge,
				fireAt = nil,
				fireStage = nil,
				staffAt = -math.huge,
			}
			states[player] = s
		end
		if staff then
			s.staffAt = now
		elseif not (kind == "Fire" and now - s.staffAt <= Send.Grace) then
			return -- no staff in the hands (a shot just after it was put away still counts)
		end
		if kind == "Aim" then
			if not Rules.due(s.aimAt, now, Send.AimRate, Send.AimSlack) then
				return
			end
			local target, held, cap = point(a, head), Rules.held(b, Send.MaxHeld), Rules.cap(c, LAST)
			if not target or held == false or not cap then
				return
			end
			s.aimAt = now
			relay(player, character, "Aim", target, held, cap)
			return
		end
		if not Rules.take(s.bucket, now, Send.Events) then
			return
		end
		if kind == "Open" or kind == "Drop" then
			relay(player, character, kind)
		elseif kind == "Float" then
			if type(a) == "boolean" then
				relay(player, character, "Float", a)
			end
		elseif kind == "Fire" then
			local stage, target, mode = Rules.stage(a, LAST), point(b, head), Rules.mode(c)
			if not stage or not target or not mode then
				return
			end
			if not Rules.cooled(s.fireAt, s.fireStage, now, Spells.Staff.Cooldown, Send.CooldownSlack) then
				return
			end
			s.fireAt, s.fireStage = now, stage
			relay(player, character, "Fire", stage, target, mode)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return StaffCast
