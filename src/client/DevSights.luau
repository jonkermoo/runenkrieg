--!strict
-- Dev sight lines (the admin panel's "Weapon" switch, Config/DevTools.Admin.Sights): while the Player's attribute is
-- on, the visible gun's (src/client/GunFx.visible: the viewmodel's in first person) Muzzle, Aim and Eject are drawn
-- as dots, and the line of fire (from Muzzle) and the line of sight (from Aim) run out `length` studs, each along its
-- attachment's -Z. Aimed, the two lines run parallel (the aiming contract): a sight that has drifted shows as lines
-- that meet or cross. Local parts under the camera: nobody else sees them and no ray hits them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools)
local GunFx = require(script.Parent.GunFx)

local S = Cfg.Admin.Sights

local DevSights = {}

local function piece(name: string, shape: Enum.PartType, color: { number }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(table.unpack(color))
	p.Parent = parent
	return p
end

local function show(player: Player): () -> ()
	local folder = Instance.new("Folder")
	folder.Name = "DevSights"
	folder.Parent = workspace.CurrentCamera
	local dots: { [string]: Part } = {}
	local lines: { [string]: Part } = {}
	for name, color in S.colors do
		dots[name] = piece(name, Enum.PartType.Ball, color, folder)
		dots[name].Size = Vector3.one * S.dot
	end
	for _, name in S.lines do
		lines[name] = piece(name .. "Line", Enum.PartType.Block, S.colors[name], folder)
		lines[name].Size = Vector3.new(S.width, S.width, S.length)
	end
	local conn = RunService.RenderStepped:Connect(function()
		local character = player.Character
		local gun = character and GunFx.visible(character)
		for name, dot in dots do
			local a = gun and gun:FindFirstChild(name)
			local line = lines[name]
			if a and a:IsA("Attachment") then
				dot.Transparency = 0
				dot.CFrame = a.WorldCFrame
				if line then
					line.Transparency = 0
					line.CFrame = a.WorldCFrame * CFrame.new(0, 0, -S.length / 2)
				end
			else
				dot.Transparency = 1
				if line then
					line.Transparency = 1
				end
			end
		end
	end)
	return function()
		conn:Disconnect()
		folder:Destroy()
	end
end

function DevSights.start(player: Player)
	local stop: (() -> ())? = nil
	local function apply()
		local on = player:GetAttribute(S.attribute) == true
		if on and not stop then
			stop = show(player)
		elseif not on and stop then
			stop()
			stop = nil
		end
	end
	player:GetAttributeChangedSignal(S.attribute):Connect(apply)
	apply()
end

return DevSights
