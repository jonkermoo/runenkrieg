--!strict
-- Blinking (docs/CHARACTERS.md Faces; Config/Uniforms.Blink): every living character within range of the camera shuts
-- its eyes for a moment every few seconds, each on its own random rhythm. A blink shows the closed face of the
-- character's current health tier (the server's "FaceTier" attribute, src/server/Bodies) and opens it again. Dead
-- characters ("FaceClosed") are left alone: the server shows their death face. Local only: nothing replicates, so
-- every player sees everyone blink, out of step.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local U = require(Shared.Config.Uniforms)
local Faces = require(Shared.Rules.Faces)

local Blink = {}

type State = { next: number, reopen: number? }

function Blink.start()
	local B = U.Blink
	local states: { [Model]: State } = setmetatable({}, { __mode = "k" }) :: any
	local rng = Random.new()

	local function decal(character: Model): Decal?
		local card = character:FindFirstChild("FaceCard")
		return card and card:FindFirstChild("face") :: Decal?
	end

	local function texture(character: Model, closed: boolean): string?
		local tier = character:GetAttribute("FaceTier")
		local f = type(tier) == "number" and U.Faces[tier]
		if not f then
			return nil
		end
		return "rbxassetid://" .. (if closed then f.closed else f.open)
	end

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local camera = workspace.CurrentCamera
		local eye = camera and camera.CFrame.Position or Vector3.zero
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if not character then
				continue
			end
			local state = states[character]
			if not state then
				state = { next = now + Faces.blinkGap(rng:NextNumber(), B.MinGap, B.MaxGap) }
				states[character] = state
			end
			local face = decal(character)
			if not face or character:GetAttribute("FaceClosed") == true then
				state.reopen = nil -- dead: the server's death face stays
				continue
			end
			if state.reopen then
				if now >= state.reopen then
					state.reopen = nil
					face.Texture = texture(character, false) or face.Texture
				end
			elseif now >= state.next then
				state.next = now + Faces.blinkGap(rng:NextNumber(), B.MinGap, B.MaxGap)
				local head = character:FindFirstChild("Head") :: BasePart?
				if head and (head.Position - eye).Magnitude <= B.Range then
					face.Texture = texture(character, true) or face.Texture
					state.reopen = now + B.Closed
				end
			end
		end
	end)
end

return Blink
