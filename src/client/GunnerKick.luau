--!strict
-- A gunner thrown back by their gun's shot (Config/Artillery.Guns `kick`; user 2026-10-29: "add some recoil animation
-- to both the gun and the player", the MG and the field gun): on every client, from the shots it sees, the gunner's
-- arms swung back `arms` degrees at the shoulders and the body tipped back `torso` at the root, easing home over
-- `time` s. It moves the R6 joints' C0 (the animations drive Transform, so it rides over whatever they play) and puts
-- each joint back exactly once its kicks are over.

local RunService = game:GetService("RunService")

local GunnerKick = {}

type Joint = { motor: Motor6D, base: CFrame, axis: Vector3, sign: number }
type Kick = { at: number, arms: number, torso: number, time: number }
type Body = { joints: { Joint }, kicks: { Kick } }

local bodies: { [Model]: Body } = {}
local bound = false

local function jointsOf(character: Model): { Joint }
	local out = {}
	local torso = character:FindFirstChild("Torso")
	local root = character:FindFirstChild("HumanoidRootPart")
	-- (R6: the shoulders swing about their joint's Z, the root tips about its X)
	for _, spec in { { torso, "Right Shoulder", Vector3.zAxis, 1 }, { torso, "Left Shoulder", Vector3.zAxis, -1 } } do
		local m = spec[1] and (spec[1] :: Instance):FindFirstChild(spec[2] :: string)
		if m and m:IsA("Motor6D") then
			table.insert(out, { motor = m, base = m.C0, axis = spec[3] :: Vector3, sign = spec[4] :: number })
		end
	end
	local rj = root and root:FindFirstChild("RootJoint")
	if rj and rj:IsA("Motor6D") then
		table.insert(out, { motor = rj, base = rj.C0, axis = Vector3.xAxis, sign = 0 })
	end
	return out
end

local function step()
	local now = os.clock()
	for character, body in bodies do
		local arms, torso = 0, 0
		for i = #body.kicks, 1, -1 do
			local k = body.kicks[i]
			local a = (now - k.at) / k.time
			if a >= 1 then
				table.remove(body.kicks, i)
			else
				local w = (1 - a) ^ 2
				arms += k.arms * w
				torso += k.torso * w
			end
		end
		local done = #body.kicks == 0 or not character.Parent
		for _, j in body.joints do
			if done or not j.motor.Parent then
				j.motor.C0 = j.base
			else
				local deg = if j.sign == 0 then torso else arms * j.sign
				j.motor.C0 = j.base * CFrame.fromAxisAngle(j.axis, math.rad(deg))
			end
		end
		if done then
			bodies[character] = nil
		end
	end
	if next(bodies) == nil then
		bound = false
		RunService:UnbindFromRenderStep("GunnerKick")
	end
end

-- a shot thrown into `character` as `kick` says (Config/Artillery.Guns `kick`)
function GunnerKick.kick(character: Model?, kick: { arms: number, torso: number, time: number }?)
	if not character or not kick then
		return
	end
	local body = bodies[character]
	if not body then
		body = { joints = jointsOf(character), kicks = {} }
		bodies[character] = body
	end
	table.insert(body.kicks, { at = os.clock(), arms = kick.arms, torso = kick.torso, time = kick.time })
	if not bound then
		bound = true
		RunService:BindToRenderStep("GunnerKick", Enum.RenderPriority.Character.Value + 1, step)
	end
end

return GunnerKick
