--!strict
-- Backpacks (docs/CHARACTERS.md "Backpacks"; user 2026-10-18/19): every soldier spawns with its kit's pack (Config/
-- Uniforms Kits `pack`) on the back of the Torso. The library model's Origin marker is the Torso center: each part
-- goes at its offset from it, keeping its imported rotation (never PivotTo the model: KNOWN_TRAPS), colored by mesh
-- name (Config/Palette.Packs). Purely visual: welded to the Torso, no collisions, never hit (CanQuery off).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local A = require(Shared.Config.Assets)
local Palette = require(Shared.Config.Palette)

local Packs = {}

-- The library model of a Config/Assets entry (ReplicatedStorage.Assets.<category>.<folder>.<name>, kept by
-- src/dev/Library sync), or nil with a warning.
local function library(name: string): Model?
	local e = A.Entries[name]
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	f = f and f:FindFirstChild(e.category)
	for _, part in string.split(e.folder, "/") do
		f = f and f:FindFirstChild(part)
	end
	local m = f and f:FindFirstChild(name)
	if not m then
		warn(`[Packs] {name} is not in the asset library: run the Library sync (CLAUDE.md)`)
		return nil
	end
	return m :: Model
end

-- Puts `entry`'s pack on the character (replacing any old one); nil takes it off.
function Packs.dress(character: Model, entry: string?)
	local old = character:FindFirstChild("Pack")
	if old then
		old:Destroy()
	end
	local torso = character:FindFirstChild("Torso") :: BasePart?
	local src = entry and library(entry)
	if not torso or not entry or not src then
		return
	end
	local model = src:Clone()
	model.Name = "Pack"
	local origin = model:FindFirstChild("Origin", true) :: BasePart?
	if not origin then
		warn(`[Packs] {entry}: the model has no Origin marker`)
		return
	end
	local frame = CFrame.new(origin.Position) -- Torso space: the Origin's position, the model's axes
	local colors = Palette.Packs[entry] or {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p ~= origin then
			local rel = frame:ToObjectSpace(p.CFrame)
			p.CFrame = torso.CFrame * rel
			local c = colors[p.Name]
			if c then
				p.Color = Color3.fromRGB(c[1], c[2], c[3])
			end
			p.Material = Enum.Material.SmoothPlastic
			p.Anchored = false
			p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
			p.CastShadow = false
			-- a Weld with the offset written down (WeldConstraints re-record theirs when they reactivate: KNOWN_TRAPS)
			local weld = Instance.new("Weld")
			weld.Part0, weld.Part1, weld.C0 = torso, p, rel
			weld.Parent = p
		end
	end
	origin:Destroy()
	model:SetAttribute("Entry", entry)
	model.Parent = character
end

return Packs
