--!strict
-- Jump shooting (Config/Firing.Airborne, Rules/Firing.airSpread): how far the local soldier's next shot may stray off
-- the barrel's line, from whether it is off the ground and how long ago it landed. Read by src/client/Firing for every
-- shot and by the admin panel's readout (src/client/DevAdminMenu).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Firing)
local F = require(Shared.Rules.Firing)

local ShotSpread = {}

local landedAt: number? = nil
local lastSpread, lastWhy = 0, "none yet"

local function attach(character: Model)
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	landedAt = nil
	humanoid.StateChanged:Connect(function(old, new)
		if new == Enum.HumanoidStateType.Landed or (old == Enum.HumanoidStateType.Freefall and new ~= old) then
			landedAt = os.clock()
		end
	end)
end

-- The spread now (degrees) and what it comes from: "air", "landing" or "steady".
function ShotSpread.now(): (number, string)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return 0, "steady"
	end
	local airborne = humanoid.FloorMaterial == Enum.Material.Air
		and humanoid:GetState() ~= Enum.HumanoidStateType.Climbing
		and humanoid:GetState() ~= Enum.HumanoidStateType.Seated
	local since = if landedAt then os.clock() - landedAt else nil
	local spread = F.airSpread(Cfg.Airborne, airborne, since, character:GetAttribute("Aiming") == true)
	return spread, if airborne then "air" elseif spread > 0 then "landing" else "steady"
end

-- `direction` turned off its line by the stray the server will roll from the dice `r1`, `r2` (Rules shotDice, from the
-- tool's "ShotKey") within the spread now; and that spread, which the shot reports (Rules serverSpread).
function ShotSpread.apply(direction: Vector3, r1: number, r2: number): (Vector3, number)
	local spread, why = ShotSpread.now()
	lastSpread, lastWhy = spread, why
	if spread <= 0 then
		return direction, spread
	end
	local right, up = F.stray(spread, r1, r2)
	return (CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(math.rad(up), -math.rad(right), 0)).LookVector,
		spread
end

-- The last shot's spread (degrees) and what it came from.
function ShotSpread.last(): (number, string)
	return lastSpread, lastWhy
end

function ShotSpread.start()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(attach)
	if player.Character then
		task.spawn(attach, player.Character)
	end
end

return ShotSpread
